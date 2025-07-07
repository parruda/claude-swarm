# frozen_string_literal: true

require "test_helper"

class OrchestratorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
    @original_env = ENV.to_h

    # Set up a default session path for tests that create McpGenerator directly
    @test_session_path = File.join(@tmpdir, "test_session")
    ENV["CLAUDE_SWARM_SESSION_PATH"] ||= @test_session_path
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    # Restore original environment
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def find_mcp_file(name)
    session_path = ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil)
    return unless session_path

    file_path = File.join(session_path, "#{name}.mcp.json")
    File.exist?(file_path) ? file_path : nil
  end

  def write_config(content)
    File.write(@config_path, content)
  end

  def create_test_config
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer instance"
            directory: ./src
            model: opus
            connections: [backend]
            tools: [Read, Edit, Bash]
            prompt: "You are the lead developer"
          backend:
            description: "Backend service instance"
            directory: ./backend
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "src"))
    Dir.mkdir(File.join(@tmpdir, "backend"))

    ClaudeSwarm::Configuration.new(@config_path)
  end

  def test_start_sets_session_path
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    # Mock system to prevent actual execution
    orchestrator.stub(:system, true) do
      capture_io do
        orchestrator.start
      end
    end

    assert(ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil))
    assert(ENV.fetch("CLAUDE_SWARM_START_DIR", nil))
    assert_match(%r{/sessions/.+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}}, ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil))
  end

  def test_start_generates_mcp_configs
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    Dir.chdir(@tmpdir) do
      orchestrator.stub(:system, true) do
        capture_io do
          orchestrator.start
        end
      end

      # MCP files are now in ~/.claude-swarm, not in the current directory
      session_path = ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil)

      assert(session_path)
      assert_path_exists(File.join(session_path, "lead.mcp.json"), "Expected lead.mcp.json to exist")
      assert_path_exists(File.join(session_path, "backend.mcp.json"), "Expected backend.mcp.json to exist")
    end
  end

  def test_start_output_messages
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    output = nil
    orchestrator.stub(:system, true) do
      output = capture_io { orchestrator.start }[0]
    end

    assert_match(/🐝 Starting Claude Swarm: Test Swarm/, output)
    assert_match(%r{📝 Session files will be saved to:.*/sessions/.+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}}, output)
    assert_match(/✓ Generated MCP configurations/, output)
    assert_match(/🚀 Launching main instance: lead/, output)
    assert_match(/Model: opus/, output)
    assert_match(/Directory:.*src/, output)
    assert_match(/Allowed tools: Read, Edit, Bash/, output)
    assert_match(/Connections: backend/, output)
  end

  def test_build_main_command_with_all_options
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Verify command array components
    assert_equal("claude", expected_command[0])
    assert_includes(expected_command, "--model")
    assert_includes(expected_command, "opus")
    assert_includes(expected_command, "--allowedTools")
    assert_includes(expected_command, "Read,Edit,Bash,mcp__backend")
    assert_includes(expected_command, "--append-system-prompt")
    assert_includes(expected_command, "You are the lead developer")
    assert_includes(expected_command, "--mcp-config")

    # Find the MCP config path in the array
    mcp_index = expected_command.index("--mcp-config")

    assert(mcp_index)
    mcp_path = expected_command[mcp_index + 1]

    assert_match(%r{/lead\.mcp\.json$}, mcp_path)
  end

  def test_build_main_command_without_tools
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # When no tools are specified and vibe is false, neither flag should be present
    refute_includes(expected_command, "--dangerously-skip-permissions")
    refute_includes(expected_command, "--allowedTools")
  end

  def test_build_main_command_without_prompt
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            tools: [Read]
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    refute_includes(expected_command, "--append-system-prompt")
  end

  def test_special_characters_in_arguments
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test's Swarm"
        main: lead
        instances:
          lead:
            description: "Test instance"
            directory: "./path with spaces"
            prompt: "You're the 'lead' developer!"
            tools: ["Bash(rm -rf *)"]
    YAML

    Dir.mkdir(File.join(@tmpdir, "path with spaces"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Verify arguments are passed correctly without manual escaping
    assert_includes(expected_command, "--append-system-prompt")
    prompt_index = expected_command.index("--append-system-prompt")

    assert_equal("You're the 'lead' developer!", expected_command[prompt_index + 1])
    assert_includes(expected_command, "Bash(rm -rf *)")
  end

  def test_debug_mode_shows_command
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, debug: true)

    output = nil
    orchestrator.stub(:system, true) do
      output = capture_io { orchestrator.start }[0]
    end

    assert_match(/🏃 Running: claude --model.*/, output)
  end

  def test_empty_connections_and_tools
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Minimal"
        main: solo
        instances:
          solo:
            description: "Solo instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    output = nil
    orchestrator.stub(:system, true) do
      output = capture_io { orchestrator.start }[0]
    end

    # Should not show empty tools or connections
    refute_match(/Tools:/, output)
    refute_match(/Connections:/, output)
  end

  def test_absolute_path_handling
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            directory: #{@tmpdir}/absolute/path
    YAML

    FileUtils.mkdir_p(File.join(@tmpdir, "absolute", "path"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Since we use Dir.chdir now, the path isn't part of the command
    # Just verify the command was captured
    assert(expected_command)
    assert_equal("claude", expected_command[0])
  end

  def test_mcp_config_path_resolution
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Find MCP config path from command array
    mcp_index = expected_command.index("--mcp-config")

    assert(mcp_index)

    mcp_path = expected_command[mcp_index + 1]

    assert(mcp_path.end_with?("/lead.mcp.json"))
    # The file will be created when the generator runs, so we can't check it exists yet
  end

  def test_build_main_command_with_prompt
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, prompt: "Execute test task")

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Verify prompt is included in command
    assert_includes(expected_command, "-p")
    p_index = expected_command.index("-p")

    assert_equal("Execute test task", expected_command[p_index + 1])
  end

  def test_build_main_command_with_prompt_requiring_escaping
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, prompt: "Fix the 'bug' in module X")

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Verify prompt with quotes is passed correctly
    assert_includes(expected_command, "-p")
    p_index = expected_command.index("-p")

    assert_equal("Fix the 'bug' in module X", expected_command[p_index + 1])
  end

  def test_output_suppression_with_prompt
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, prompt: "Test prompt")

    output = nil
    orchestrator.stub(:system, true) do
      output = capture_io { orchestrator.start }[0]
    end

    # All startup messages should be suppressed
    refute_match(/🐝 Starting Claude Swarm/, output)
    refute_match(/📝 Session logs will be saved/, output)
    refute_match(/✓ Generated MCP configurations/, output)
    refute_match(/🚀 Launching main instance/, output)
    refute_match(/Model:/, output)
    refute_match(/Directory:/, output)
    refute_match(/Tools:/, output)
    refute_match(/Connections:/, output)
  end

  def test_output_shown_without_prompt
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    output = nil
    orchestrator.stub(:system, true) do
      output = capture_io { orchestrator.start }[0]
    end

    # All startup messages should be shown
    assert_match(/🐝 Starting Claude Swarm/, output)
    assert_match(/📝 Session files will be saved/, output)
    assert_match(/✓ Generated MCP configurations/, output)
    assert_match(/🚀 Launching main instance/, output)
  end

  def test_debug_mode_suppressed_with_prompt
    ENV["DEBUG"] = "true"
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, prompt: "Debug test")

    output = nil
    orchestrator.stub(:system, true) do
      output = capture_io { orchestrator.start }[0]
    end

    # Debug output should also be suppressed with prompt
    refute_match(/Running:/, output)
  end

  def test_vibe_mode_with_prompt
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, vibe: true, prompt: "Vibe test")

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Should include both vibe flag and prompt
    assert_includes(expected_command, "--dangerously-skip-permissions")
    assert_includes(expected_command, "-p")
    p_index = expected_command.index("-p")

    assert_equal("Vibe test", expected_command[p_index + 1])
  end

  def test_default_prompt_when_no_prompt_specified
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Should add default prompt when no -p flag is provided
    last_arg = expected_command.last

    assert_match(/You are the lead developer\n\nNow just say 'I am ready to start'/, last_arg)
  end

  def test_default_prompt_for_instance_without_custom_prompt
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            tools: [Read]
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system, lambda { |*args|
      expected_command = args
      true
    }) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Should just have the generic prompt when instance has no custom prompt
    last_arg = expected_command.last

    assert_equal("\n\nNow just say 'I am ready to start'", last_arg)
  end

  def test_before_commands_feature_exists
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        before:
          - "echo 'test'"
        instances:
          lead:
            description: "Test instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    # Test that configuration reads before commands correctly
    assert_equal(["echo 'test'"], config.before_commands)

    # Verify orchestrator can be created with before commands config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    assert_instance_of(ClaudeSwarm::Orchestrator, orchestrator)
  end

  def test_before_commands_not_executed_on_restore
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        before:
          - "echo 'Should not run on restore'"
        instances:
          lead:
            description: "Test instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    # Simulate restoration
    restore_session_path = File.join(@tmpdir, "session")
    FileUtils.mkdir_p(restore_session_path)

    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, restore_session_path: restore_session_path)

    command_executed = false
    orchestrator.stub(:`, lambda { |_cmd|
      command_executed = true
      "Should not see this\n"
    }) do
      orchestrator.stub(:system, true) do
        output = capture_io { orchestrator.start }[0]

        refute(command_executed, "Before commands should not execute during session restoration")
        refute_match(/Executing before commands/, output)
      end
    end
  end

  def test_before_commands_with_empty_array
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        before: []
        instances:
          lead:
            description: "Test instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    command_executed = false
    orchestrator.stub(:`, lambda { |_cmd|
      command_executed = true
      "Should not execute\n"
    }) do
      orchestrator.stub(:system, true) do
        output = capture_io { orchestrator.start }[0]

        refute(command_executed, "No commands should be executed with empty before array")
        refute_match(/Executing before commands/, output)
      end
    end
  end

  def test_main_pid_file_creation
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    # Mock system! to prevent actual execution
    orchestrator.stub(:system!, true) do
      capture_io { orchestrator.start }
    end

    # Get the session path that was created
    session_path = orchestrator.instance_variable_get(:@session_path)

    assert(session_path, "Session path should be set")

    # Verify main_pid file was created
    main_pid_file = File.join(session_path, "main_pid")

    assert_path_exists(main_pid_file, "main_pid file should exist")

    # The PID should be the current process PID
    pid_content = File.read(main_pid_file).strip

    assert_equal(Process.pid.to_s, pid_content, "main_pid should contain current process PID")
  end

  def test_before_commands_execute_in_main_instance_directory
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        before:
          - "pwd > before_pwd.txt"
        instances:
          lead:
            description: "Test instance"
            directory: ./test_dir
    YAML

    test_dir = File.join(@tmpdir, "test_dir")
    FileUtils.mkdir_p(test_dir)

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    # Mock system! to prevent actual execution
    orchestrator.stub(:system!, true) do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Verify the before command was executed in the main instance directory
    pwd_file = File.join(test_dir, "before_pwd.txt")

    assert_path_exists(pwd_file, "before_pwd.txt should be created in main instance directory")

    # Check that the recorded pwd matches the expected directory
    recorded_pwd = File.read(pwd_file).strip
    expected_pwd = File.expand_path(test_dir)
    # Normalize both paths to handle symlink resolution differences
    assert_equal(File.realpath(expected_pwd), File.realpath(recorded_pwd), "Before commands should execute in main instance directory")
  end

  def test_before_commands_fail_stops_execution
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        before:
          - "exit 1"
        instances:
          lead:
            description: "Test instance"
            directory: .
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    system_called = false
    orchestrator.stub(:system!, lambda { |*_args|
      system_called = true
      true
    }) do
      orchestrator.stub(:cleanup_processes, nil) do
        orchestrator.stub(:cleanup_run_symlink, nil) do
          orchestrator.stub(:cleanup_worktrees, nil) do
            orchestrator.stub(:exit, lambda { |code|
              assert_equal(1, code, "Should exit with code 1 when before commands fail")
              raise SystemExit, "exit(#{code})"
            }) do
              Dir.chdir(@tmpdir) do
                assert_raises(SystemExit) do
                  capture_io { orchestrator.start }
                end
              end
            end
          end
        end
      end
    end

    refute(system_called, "Main instance should not be launched when before commands fail")
  end
end
