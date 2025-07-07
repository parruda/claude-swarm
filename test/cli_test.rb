# frozen_string_literal: true

require "test_helper"

class CLITest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@tmpdir)
    @cli = ClaudeSwarm::CLI.new
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  def write_config(filename, content)
    File.write(filename, content)
  end

  def capture_cli_output(&)
    capture_io(&)
  end

  def test_exit_on_failure
    assert_predicate(ClaudeSwarm::CLI, :exit_on_failure?)
  end

  def test_version_command
    output, = capture_cli_output { @cli.version }

    assert_match(/Claude Swarm \d+\.\d+\.\d+/, output)
  end

  def test_default_task_is_start
    assert_equal("start", ClaudeSwarm::CLI.default_task)
  end

  def test_start_with_missing_config_file
    assert_raises(SystemExit) do
      capture_cli_output { @cli.start("nonexistent.yml") }
    end
  end

  def test_start_with_invalid_yaml
    write_config("invalid.yml", "invalid: yaml: syntax:")

    assert_raises(SystemExit) do
      capture_cli_output { @cli.start("invalid.yml") }
    end
  end

  def test_start_with_configuration_error
    write_config("bad-config.yml", <<~YAML)
      version: 2
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    out, = capture_cli_output do
      assert_raises(SystemExit) { @cli.start("bad-config.yml") }
    end

    assert_match(/Unsupported version/, out)
  end

  def test_start_with_valid_config
    write_config("valid.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    # Mock the orchestrator to prevent actual execution
    orchestrator_mock = Minitest::Mock.new
    orchestrator_mock.expect(:start, nil)

    ClaudeSwarm::Orchestrator.stub(:new, orchestrator_mock) do
      capture_cli_output { @cli.start("valid.yml") }
    end

    orchestrator_mock.verify
  end

  def test_start_with_options
    write_config("custom.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    @cli.options = { config: "custom.yml" }

    orchestrator_mock = Minitest::Mock.new
    orchestrator_mock.expect(:start, nil)

    ClaudeSwarm::Orchestrator.stub(:new, orchestrator_mock) do
      capture_cli_output { @cli.start }
    end

    orchestrator_mock.verify
  end

  def test_start_with_prompt_option
    write_config("valid.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"

    YAML

    @cli.options = { prompt: "Test prompt for non-interactive mode" }

    orchestrator_mock = Minitest::Mock.new
    orchestrator_mock.expect(:start, nil)

    generator_mock = Minitest::Mock.new

    # Verify that prompt is passed to orchestrator
    ClaudeSwarm::McpGenerator.stub(:new, generator_mock) do
      ClaudeSwarm::Orchestrator.stub(:new, lambda { |_config, _generator, **options|
        assert_equal("Test prompt for non-interactive mode", options[:prompt])
        assert_nil(options[:vibe])
        orchestrator_mock
      }) do
        output, = capture_cli_output { @cli.start("valid.yml") }
        # Verify that startup message is suppressed when prompt is provided
        refute_match(/Starting Claude Swarm/, output)
      end
    end

    orchestrator_mock.verify
  end

  def test_start_without_prompt_shows_message
    write_config("valid.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    @cli.options = {}

    orchestrator_mock = Minitest::Mock.new
    orchestrator_mock.expect(:start, nil)

    ClaudeSwarm::Orchestrator.stub(:new, orchestrator_mock) do
      output, = capture_cli_output { @cli.start("valid.yml") }
      # Verify that startup message is shown when prompt is not provided
      assert_match(/Starting Claude Swarm from valid\.yml\.\.\./, output)
    end

    orchestrator_mock.verify
  end

  def test_mcp_serve_with_all_options
    @cli.options = {
      name: "test_instance",
      directory: "/test/dir",
      model: "opus",
      prompt: "Test prompt",
      allowed_tools: ["Read", "Edit"],
      mcp_config_path: "/path/to/mcp.json",
      debug: false,
      calling_instance: "parent_instance",
    }

    server_mock = Minitest::Mock.new
    server_mock.expect(:start, nil)

    expected_config = {
      name: "test_instance",
      directory: "/test/dir",
      directories: ["/test/dir"],
      model: "opus",
      prompt: "Test prompt",
      description: nil,
      allowed_tools: ["Read", "Edit"],
      disallowed_tools: [],
      connections: [],
      mcp_config_path: "/path/to/mcp.json",
      vibe: false,
      instance_id: nil,
      claude_session_id: nil,
      provider: nil,
      temperature: nil,
      api_version: nil,
      openai_token_env: nil,
      base_url: nil,
    }

    ClaudeSwarm::ClaudeMcpServer.stub(:new, lambda { |config, calling_instance:, calling_instance_id: nil| # rubocop:disable Lint/UnusedBlockArgument
      assert_equal(expected_config, config)
      assert_equal("parent_instance", calling_instance)
      server_mock
    }) do
      @cli.mcp_serve
    end

    server_mock.verify
  end

  def test_mcp_serve_with_minimal_options
    @cli.options = {
      name: "minimal",
      directory: ".",
      model: "sonnet",
      calling_instance: "test_caller",
    }

    server_mock = Minitest::Mock.new
    server_mock.expect(:start, nil)

    expected_config = {
      name: "minimal",
      directory: ".",
      directories: ["."],
      model: "sonnet",
      prompt: nil,
      description: nil,
      allowed_tools: [],
      disallowed_tools: [],
      connections: [],
      mcp_config_path: nil,
      vibe: false,
      instance_id: nil,
      claude_session_id: nil,
      provider: nil,
      temperature: nil,
      api_version: nil,
      openai_token_env: nil,
      base_url: nil,
    }

    ClaudeSwarm::ClaudeMcpServer.stub(:new, lambda { |config, calling_instance:, calling_instance_id: nil| # rubocop:disable Lint/UnusedBlockArgument
      assert_equal(expected_config, config)
      assert_equal("test_caller", calling_instance)
      server_mock
    }) do
      @cli.mcp_serve
    end

    server_mock.verify
  end

  def test_mcp_serve_error_handling
    @cli.options = {
      name: "error",
      directory: ".",
      model: "sonnet",
      debug: false,
      calling_instance: "test_caller",
    }

    ClaudeSwarm::ClaudeMcpServer.stub(:new, lambda { |_, calling_instance:, calling_instance_id: nil| # rubocop:disable Lint/UnusedBlockArgument
      raise StandardError, "Test error"
    }) do
      out, = capture_cli_output do
        assert_raises(SystemExit) { @cli.mcp_serve }
      end

      assert_match(/Error starting MCP server: Test error/, out)
      refute_match(/backtrace/, out) # Debug is false
    end
  end

  def test_mcp_serve_error_with_debug
    @cli.options = {
      name: "error",
      directory: ".",
      model: "sonnet",
      debug: true,
      calling_instance: "test_caller",
    }

    ClaudeSwarm::ClaudeMcpServer.stub(:new, lambda { |_, calling_instance:, calling_instance_id: nil| # rubocop:disable Lint/UnusedBlockArgument
      raise StandardError, "Test error"
    }) do
      out, = capture_cli_output do
        assert_raises(SystemExit) { @cli.mcp_serve }
      end

      assert_match(/Error starting MCP server: Test error/, out)
      assert_match(/cli_test\.rb/, out) # Should show backtrace
    end
  end

  def test_start_unexpected_error_without_verbose
    write_config("valid.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    @cli.options = { config: "valid.yml", verbose: false }

    ClaudeSwarm::Configuration.stub(:new, lambda { |_, _|
      raise StandardError, "Unexpected test error"
    }) do
      out, = capture_cli_output do
        assert_raises(SystemExit) { @cli.start }
      end

      assert_match(/Unexpected error: Unexpected test error/, out)
      refute_match(/backtrace/, out)
    end
  end

  def test_start_unexpected_error_with_verbose
    write_config("valid.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    @cli.options = { config: "valid.yml", verbose: true }

    ClaudeSwarm::Configuration.stub(:new, lambda { |_, _|
      raise StandardError, "Unexpected test error"
    }) do
      out, = capture_cli_output do
        assert_raises(SystemExit) { @cli.start }
      end

      assert_match(/Unexpected error: Unexpected test error/, out)
      assert_match(/cli_test\.rb/, out) # Should show backtrace
    end
  end

  def test_cli_help_messages
    # Skip these tests as they depend on the executable being in the PATH
    skip("Skipping executable tests")
  end

  def test_start_help
    # Skip these tests as they depend on the executable being in the PATH
    skip("Skipping executable tests")
  end

  def test_mcp_serve_help
    # Skip these tests as they depend on the executable being in the PATH
    skip("Skipping executable tests")
  end

  def test_generate_without_claude_installed
    # Mock system call to simulate Claude not being installed (command -v fails)
    @cli.stub(:system, lambda { |cmd|
      !cmd.include?("command -v claude")
    }) do
      out, = capture_cli_output do
        assert_raises(SystemExit) { @cli.generate }
      end

      assert_match(/Claude CLI is not installed or not in PATH/, out)
      assert_match(/To install Claude CLI, visit:/, out)
    end
  end

  def test_generate_with_claude_installed
    # Mock system call to simulate Claude being installed (command -v succeeds)
    @cli.stub(:system, lambda { |cmd|
      cmd.include?("command -v claude") || false
    }) do
      # Read the actual template file before stubbing
      actual_template_path = File.expand_path("../lib/claude_swarm/templates/generation_prompt.md.erb", __dir__)
      template_content = File.read(actual_template_path)
      # Mock File operations for README and template
      File.stub(:exist?, ->(path) { path.include?("README.md") || path.include?("generation_prompt.md.erb") }) do
        File.stub(:read, lambda { |path|
          if path.include?("README.md")
            "Mock README content"
          elsif path.include?("generation_prompt.md.erb")
            template_content
          else
            ""
          end
        }) do
          # Stub exec to prevent actual execution and capture the command
          exec_called = false
          exec_args = nil

          @cli.stub(:exec, lambda { |*args|
            exec_called = true
            exec_args = args
            # Prevent actual exec
            nil
          }) do
            @cli.options = { model: "sonnet" }
            @cli.generate

            assert(exec_called, "exec should have been called")
            assert_equal("claude", exec_args[0])
            assert_equal("--model", exec_args[1])
            assert_equal("sonnet", exec_args[2])
            # Test that the prompt includes README content
            assert_match(%r{<full_readme>.*Mock README content.*</full_readme>}m, exec_args[3])
          end
        end
      end
    end
  end

  def test_generate_without_output_file_includes_naming_instructions
    @cli.stub(:system, true) do
      exec_args = nil

      @cli.stub(:exec, lambda { |*args|
        exec_args = args
        nil
      }) do
        @cli.options = { model: "sonnet" }
        @cli.generate

        # Check that the prompt includes instructions to name based on function
        assert_match(/name the file based on the swarm's function/, exec_args[3])
        assert_match(/web-dev-swarm\.yml/, exec_args[3])
        assert_match(/data-pipeline-swarm\.yml/, exec_args[3])
      end
    end
  end

  def test_generate_with_custom_output_file
    @cli.stub(:system, true) do
      exec_args = nil

      @cli.stub(:exec, lambda { |*args|
        exec_args = args
        nil
      }) do
        @cli.options = { output: "my-custom-config.yml", model: "sonnet" }
        @cli.generate

        # Check that the custom output file is mentioned in the prompt
        assert_match(/save it to: my-custom-config\.yml/, exec_args[3])
      end
    end
  end

  def test_generate_with_custom_model
    @cli.stub(:system, true) do
      exec_args = nil

      @cli.stub(:exec, lambda { |*args|
        exec_args = args
        nil
      }) do
        @cli.options = { output: "claude-swarm.yml", model: "opus" }
        @cli.generate

        assert_equal("opus", exec_args[2])
      end
    end
  end

  def test_generate_includes_readme_content_if_exists
    # Create a mock README file
    readme_content = "# Claude Swarm\nThis is a test README content."

    # Read the actual template file before stubbing
    actual_template_path = File.expand_path("../lib/claude_swarm/templates/generation_prompt.md.erb", __dir__)
    template_content = File.read(actual_template_path)

    File.stub(:exist?, ->(path) { path.include?("README.md") || path.include?("generation_prompt.md.erb") }) do
      File.stub(:read, lambda { |path|
        if path.include?("README.md")
          readme_content
        elsif path.include?("generation_prompt.md.erb")
          template_content
        else
          ""
        end
      }) do
        @cli.stub(:system, true) do
          exec_args = nil

          @cli.stub(:exec, lambda { |*args|
            exec_args = args
            nil
          }) do
            @cli.options = { model: "sonnet" }
            @cli.generate

            # The prompt should include the README content in full_readme tags
            assert_match(%r{<full_readme>.*# Claude Swarm.*This is a test README content.*</full_readme>}m, exec_args[3])
          end
        end
      end
    end
  end

  def test_build_generation_prompt_with_output_file
    readme_content = "Test README content for Claude Swarm"
    prompt = @cli.send(:build_generation_prompt, readme_content, "output.yml")

    # Test that a prompt is generated
    assert_kind_of(String, prompt)
    assert_operator(prompt.length, :>, 100)

    # Test that output file is mentioned
    assert_match(/output\.yml/, prompt)

    # Test that README content is included
    assert_match(%r{<full_readme>.*Test README content for Claude Swarm.*</full_readme>}m, prompt)
  end

  def test_build_generation_prompt_without_output_file
    readme_content = "Test README content"
    prompt = @cli.send(:build_generation_prompt, readme_content, nil)

    # Test that a prompt is generated
    assert_kind_of(String, prompt)
    assert_operator(prompt.length, :>, 100)

    # Test that it includes file naming instructions when no output specified
    assert_match(/name the file based on the swarm's function/, prompt)

    # Test that README content is included
    assert_match(%r{<full_readme>.*Test README content.*</full_readme>}m, prompt)
  end
end
