# frozen_string_literal: true

module TestHelpers
  module FileHelpers
    def with_temp_dir
      Dir.mktmpdir do |tmpdir|
        original_dir = Dir.pwd
        begin
          Dir.chdir(tmpdir)
          yield tmpdir
        ensure
          Dir.chdir(original_dir)
        end
      end
    end

    def write_config_file(filename, content)
      File.write(filename, content)
    end

    def create_directories(*dirs)
      dirs.each { |dir| FileUtils.mkdir_p(dir) }
    end

    def assert_file_exists(path, message = nil)
      assert_path_exists(path, message || "Expected file #{path} to exist")
    end

    def assert_directory_exists(path, message = nil)
      assert_predicate(Pathname.new(path), :directory?, message || "Expected directory #{path} to exist")
    end

    def read_json_file(path)
      JSON.parse(File.read(path))
    end
  end

  module MockHelpers
    def mock_executor(responses = {})
      mock = Minitest::Mock.new

      # Default responses
      mock.expect(:session_id, responses[:session_id] || "test-session-1")
      mock.expect(:has_session?, responses[:has_session] || true)
      mock.expect(:working_directory, responses[:working_directory] || Dir.pwd)

      mock.expect(:execute, responses[:execute], [String, Hash]) if responses[:execute]

      mock.expect(:reset_session, nil) if responses[:reset_session]

      mock
    end

    def mock_orchestrator
      mock = Minitest::Mock.new
      mock.expect(:start, nil)
      mock
    end

    def mock_mcp_server
      mock = Minitest::Mock.new
      mock.expect(:register_tool, nil, [Class])
      mock.expect(:register_tool, nil, [Class])
      mock.expect(:register_tool, nil, [Class])
      mock.expect(:start, nil)
      mock
    end

    def with_mocked_exec
      captured_command = nil
      Object.any_instance.stub(:exec, ->(cmd) { captured_command = cmd }) do
        yield captured_command
      end
      captured_command
    end
  end

  module AssertionHelpers
    def assert_includes_all(collection, items, message = nil)
      items.each do |item|
        assert_includes(
          collection,
          item,
          message || "Expected #{collection.inspect} to include #{item.inspect}",
        )
      end
    end

    def assert_json_schema(json, schema)
      schema.each do |key, expected_type|
        assert(json.key?(key), "Expected JSON to have key '#{key}'")

        case expected_type
        when Class

          assert_kind_of(
            expected_type,
            json[key],
            "Expected #{key} to be #{expected_type}, got #{json[key].class}",
          )
        when Hash
          assert_kind_of(Hash, json[key])
          assert_json_schema(json[key], expected_type)
        when Array

          assert_kind_of(Array, json[key])
        end
      end
    end

    def assert_command_includes(command, *parts)
      parts.each do |part|
        assert_includes(
          command,
          part,
          "Expected command to include '#{part}'\nCommand: #{command}",
        )
      end
    end

    def assert_error_message(error_class, message_pattern, &)
      error = assert_raises(error_class, &)
      assert_match(message_pattern, error.message)
      error
    end
  end

  module CLIHelpers
    def capture_cli_output(&)
      capture_io(&)
    end

    def run_cli_command(command, args = [])
      original_argv = ARGV.dup
      ARGV.clear
      ARGV.concat([command] + args)

      output = capture_io { ClaudeSwarm::CLI.start }
      output
    ensure
      ARGV.clear
      ARGV.concat(original_argv)
    end

    def with_cli_options(options = {})
      cli = ClaudeSwarm::CLI.new
      cli.options = options
      cli
    end
  end

  module SwarmHelpers
    def create_basic_swarm(config_content = nil)
      config_content ||= Fixtures::SwarmConfigs.minimal
      write_config_file("claude-swarm.yml", config_content)

      config = ClaudeSwarm::Configuration.new("claude-swarm.yml")
      generator = ClaudeSwarm::McpGenerator.new(config)
      orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

      [config, generator, orchestrator]
    end

    def assert_valid_mcp_config(path)
      assert_file_exists(path)

      mcp_config = read_json_file(path)

      assert_json_schema(mcp_config, {
        "mcpServers" => Hash,
      })

      mcp_config
    end

    def assert_mcp_server_config(server_config, expected_type)
      assert_equal(expected_type, server_config["type"])

      case expected_type
      when "stdio"
        assert(server_config.key?("command"))
        assert(server_config.key?("args"))
      when "sse", "http"

        assert(server_config.key?("url"))
      end
    end
  end

  module LogHelpers
    def with_captured_logs
      original_logger = ClaudeSwarm::ClaudeMcpServer.logger

      string_io = StringIO.new
      test_logger = Logger.new(string_io)
      ClaudeSwarm::ClaudeMcpServer.logger = test_logger

      yield

      string_io.string
    ensure
      ClaudeSwarm::ClaudeMcpServer.logger = original_logger
    end

    def assert_log_contains(log_content, *patterns)
      patterns.each do |pattern|
        assert_match(
          pattern,
          log_content,
          "Expected log to contain #{pattern.inspect}",
        )
      end
    end

    def find_log_files(pattern = "session.log")
      session_path = ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil)
      return [] unless session_path && Dir.exist?(session_path)

      Dir.glob(File.join(session_path, pattern))
    end
  end

  module McpHelpers
    def find_mcp_file(instance_name)
      # MCP files are now in the session path set by the orchestrator
      session_path = ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil)
      return unless session_path && Dir.exist?(session_path)

      file_path = File.join(session_path, "#{instance_name}.mcp.json")
      File.exist?(file_path) ? file_path : nil
    end

    def read_mcp_config(instance_name)
      mcp_file = find_mcp_file(instance_name)
      raise "MCP file not found for instance: #{instance_name}" unless mcp_file

      JSON.parse(File.read(mcp_file))
    end

    def find_latest_session_dir
      # Just return the current session path
      ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil)
    end

    def assert_valid_instance_metadata(metadata, instance_name, expected_config)
      assert_includes(
        metadata[:instance_configs].keys,
        instance_name,
        "Expected metadata to include instance '#{instance_name}'",
      )

      instance_config = metadata[:instance_configs][instance_name]

      assert_equal(
        expected_config[:worktree_config],
        instance_config[:worktree_config],
        "Worktree config mismatch for instance '#{instance_name}'",
      )
      assert_equal(
        expected_config[:directories],
        instance_config[:directories],
        "Directories mismatch for instance '#{instance_name}'",
      )
      assert_equal(
        expected_config[:worktree_paths],
        instance_config[:worktree_paths],
        "Worktree paths mismatch for instance '#{instance_name}'",
      )
    end

    def calculate_worktree_path(repo_dir, worktree_name, session_id = "default")
      repo_name = File.basename(repo_dir)
      repo_hash = Digest::SHA256.hexdigest(repo_dir)[0..7]
      ClaudeSwarm.joined_worktrees_dir(session_id, "#{repo_name}-#{repo_hash}", worktree_name)
    end
  end

  module SystemUtilsHelpers
    # Exit status constants
    EXIT_STATUS_TIMEOUT = 143 # 128 + 15 (SIGTERM)
    EXIT_STATUS_COMMAND_NOT_FOUND = 127
    EXIT_STATUS_TIMEOUT_GNU = 124 # GNU timeout command exit status

    def assert_system_command_fails(command_args, expected_exit_status)
      _output, err = capture_subprocess_io do
        error = assert_raises(ClaudeSwarm::Error) do
          if command_args.is_a?(Array)
            @subject.system!(*command_args)
          else
            @subject.system!(command_args)
          end
        end
        assert_match(/Command failed with exit status #{expected_exit_status}/, error.message)

        # Verify command string is included in error message
        command_str = command_args.is_a?(Array) ? command_args.join(" ") : command_args

        assert_match(/#{Regexp.escape(command_str)}/, error.message)
      end

      # Don't assert output is empty since commands like 'ls' may write to stdout/stderr
      assert_match(/❌ Command failed with exit status: #{expected_exit_status}/, err)
    end

    def assert_system_command_times_out(command_args)
      _output, err = capture_subprocess_io do
        result = if command_args.is_a?(Array)
          @subject.system!(*command_args)
        else
          @subject.system!(command_args)
        end

        refute(result) # system returns false for non-zero exit
      end

      # Don't assert output is empty since commands may write to stdout/stderr
      command_str = command_args.is_a?(Array) ? command_args.join(" ") : command_args

      assert_match(/⏱️ Command timeout: #{Regexp.escape(command_str)}/, err)
    end

    def assert_system_command_succeeds(command_args)
      _output, _err = capture_subprocess_io do
        result = if command_args.is_a?(Array)
          @subject.system!(*command_args)
        else
          @subject.system!(command_args)
        end

        assert(result)
      end

      # Don't assert output is empty since successful commands may produce output
    end

    # Platform-safe check for command availability
    def command_available?(command)
      if RUBY_PLATFORM =~ /mswin|mingw|cygwin/
        system("where #{command} > NUL 2>&1")
      else
        system("which #{command} > /dev/null 2>&1")
      end
    end
  end

  module SwarmSDKHelpers
    # Helper to create agent definitions with sensible defaults for testing
    #
    # @param name [Symbol, String] Agent name
    # @param config [Hash] Agent configuration (optional fields)
    # @return [SwarmSDK::Agent::Definition] Fully configured agent definition
    #
    # @example
    #   swarm.add_agent(create_agent(name: :test))
    #   swarm.add_agent(create_agent(name: :backend, tools: [:Read, :Write]))
    def create_agent(name:, **config)
      # Provide sensible defaults for testing
      config[:description] ||= "Test agent #{name}"
      config[:model] ||= "gpt-5"
      config[:system_prompt] ||= "Test"
      config[:directory] ||= "."

      SwarmSDK::Agent::Definition.new(name, config)
    end

    # Helper to create a test scratchpad with temp file persistence
    # This prevents tests from writing to .swarm/scratchpad.json
    #
    # @return [SwarmSDK::Tools::Stores::Scratchpad] Scratchpad with temp file persistence
    def create_test_scratchpad
      # Create a volatile scratchpad for testing (no persistence)
      SwarmSDK::Tools::Stores::ScratchpadStorage.new
    end

    # Clean up test scratchpad files
    def cleanup_test_scratchpads
      return unless defined?(@test_scratchpad_files)

      @test_scratchpad_files&.each do |path|
        File.delete(path) if File.exist?(path)
      end
      @test_scratchpad_files = []
    end
  end
end

# Include all helpers in test classes
module Minitest
  class Test
    include TestHelpers::FileHelpers
    include TestHelpers::MockHelpers
    include TestHelpers::AssertionHelpers
    include TestHelpers::CLIHelpers
    include TestHelpers::SwarmHelpers
    include TestHelpers::LogHelpers
    include TestHelpers::McpHelpers
    include TestHelpers::SystemUtilsHelpers
    include TestHelpers::SwarmSDKHelpers
  end
end
