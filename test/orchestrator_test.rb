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

  def test_initializer_sets_session_path
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)

    # Session path should be set during initialization
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    # Test behavior, not format: environment variables should be set
    assert(ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil), "CLAUDE_SWARM_SESSION_PATH should be set")

    # Session path should be available and match environment
    assert(orchestrator.session_path, "Orchestrator should have a session path")
    assert_equal(ENV["CLAUDE_SWARM_SESSION_PATH"], orchestrator.session_path)

    # Session path should be a valid directory path
    assert(
      orchestrator.session_path.start_with?("/") || orchestrator.session_path.match?(/^[A-Za-z]:/),
      "Session path should be an absolute path",
    )
  end

  def test_start_generates_mcp_configs
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
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

  def test_start_creates_necessary_files_and_runs
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    # Test behavior: start should complete without errors
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Verify essential files were created
    session_path = orchestrator.session_path

    assert_path_exists(File.join(session_path, "lead.mcp.json"), "Lead MCP config should be created")
    assert_path_exists(File.join(session_path, "backend.mcp.json"), "Backend MCP config should be created")
    assert_path_exists(File.join(session_path, "config.yml"), "Config should be copied to session")
    assert_path_exists(File.join(session_path, "root_directory"), "Root directory file should be created")
  end

  def test_build_main_command_with_all_options
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      expected_command = args
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Verify command array components
    assert_equal("claude", expected_command[0])
    # Only check for model if ANTHROPIC_MODEL is not set
    unless ENV["ANTHROPIC_MODEL"]
      assert_includes(expected_command, "--model")
      assert_includes(expected_command, "opus")
    end

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
    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      expected_command = args
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
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
    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      expected_command = args
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
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
    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      expected_command = args
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
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
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
      output = capture_io { orchestrator.start }[0]
    end

    # The debug output should show the command, but --model may not be present if ANTHROPIC_MODEL is set
    assert_match(/🏃 Running: claude/, output)
  end

  def test_build_main_command_includes_settings_when_hooks_exist
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            directory: #{@tmpdir}/src
            model: opus
            allowed_tools: [Read, Edit]
            hooks:
              PreToolUse:
                - matcher: "Write"
                  hooks:
                    - type: "command"
                      command: "echo 'pre-hook'"
    YAML

    Dir.mkdir(File.join(@tmpdir, "src"))
    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      expected_command = args
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Should include --settings flag
    assert_includes(expected_command, "--settings")

    # Find the settings path in the array
    settings_index = expected_command.index("--settings")

    assert(settings_index)

    settings_path = expected_command[settings_index + 1]

    assert_match(/lead_settings\.json$/, settings_path)
    assert_path_exists(settings_path, "Settings file should exist at #{settings_path}")
  end

  def test_build_main_command_always_has_settings_for_session_start_hook
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      expected_command = args
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Should always include --settings flag for main instance (due to SessionStart hook)
    assert_includes(expected_command, "--settings")
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
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
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
            model: sonnet
    YAML

    FileUtils.mkdir_p(File.join(@tmpdir, "absolute", "path"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      expected_command = args
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    assert(expected_command, "Expected command should not be nil")
    assert_equal("claude", expected_command[0])
  end

  def test_mcp_config_path_resolution
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      expected_command = args
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
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
    orchestrator.stub(:stream_to_session_log, lambda { |*args, **_kwargs|
      expected_command = args
      true
    }) do
      capture_io { orchestrator.start }
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
    orchestrator.stub(:stream_to_session_log, lambda { |*args, **_kwargs|
      expected_command = args
      true
    }) do
      capture_io { orchestrator.start }
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
    orchestrator.stub(:stream_to_session_log, lambda { |*_args, **_kwargs| true }) do
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
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
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
    orchestrator.stub(:stream_to_session_log, lambda { |*_args, **_kwargs| true }) do
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
    orchestrator.stub(:stream_to_session_log, lambda { |*args, **_kwargs|
      expected_command = args
      true
    }) do
      capture_io { orchestrator.start }
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
    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      expected_command = args
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Should add instance prompt via --append-system-prompt
    append_prompt_index = expected_command.index("--append-system-prompt")

    assert(append_prompt_index, "--append-system-prompt flag should be present")
    assert_equal("You are the lead developer", expected_command[append_prompt_index + 1])
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
    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      expected_command = args
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Should not add --append-system-prompt when instance has no custom prompt
    refute_includes(expected_command, "--append-system-prompt")
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
      orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
        block&.call(12345)
        true
      }) do
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
      orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
        block&.call(12345)
        true
      }) do
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

    # Mock system_with_pid! to prevent actual execution
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
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

    # Mock system_with_pid! to prevent actual execution
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
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
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      system_called = true
      block&.call(12345)
      true
    }) do
      orchestrator.stub(:cleanup_processes, nil) do
        orchestrator.stub(:cleanup_run_symlink, nil) do
          orchestrator.stub(:cleanup_worktrees, nil) do
            orchestrator.stub(:exit, lambda { |code|
              assert_equal(1, code, "Should exit with code 1 when before commands fail")
              raise SystemExit, "exit(#{code})"
            }) do
              assert_raises(SystemExit) do
                capture_io { orchestrator.start }
              end
            end
          end
        end
      end
    end

    refute(system_called, "Main instance should not be launched when before commands fail")
  end

  def test_after_commands_feature_exists
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        after:
          - "echo 'cleanup test'"
        instances:
          lead:
            description: "Test instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    # Test that configuration reads after commands correctly
    assert_equal(["echo 'cleanup test'"], config.after_commands)

    # Verify orchestrator can be created with after commands config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    assert_instance_of(ClaudeSwarm::Orchestrator, orchestrator)
  end

  def test_after_commands_execute_after_main_instance
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        after:
          - "echo 'Running after command' > after_output.txt"
        instances:
          lead:
            description: "Test instance"
            directory: .
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    generator.stub(:generate_all, nil) do
      orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

      system_called = false
      after_executed = false

      # Mock execute_after_commands to verify it's called
      orchestrator.stub(:execute_after_commands?, lambda { |commands, chdir:|
        after_executed = true

        assert_equal(["echo 'Running after command' > after_output.txt"], commands)
        # Actually execute the command for verification using the provided chdir
        commands.each { |cmd| system(cmd, chdir: chdir) }
        true
      }) do
        orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
          system_called = true
          block&.call(12345)
          true
        }) do
          orchestrator.stub(:cleanup_processes, nil) do
            orchestrator.stub(:cleanup_run_symlink, nil) do
              orchestrator.stub(:cleanup_worktrees, nil) do
                capture_io { orchestrator.start }
              end
            end
          end
        end
      end

      assert(system_called, "Main instance should be launched")
      assert(after_executed, "After commands should be executed")

      # Verify the command actually ran
      output_file = File.join(@tmpdir, "after_output.txt")

      assert_path_exists(output_file)
      assert_match(/Running after command/, File.read(output_file))
    end
  end

  def test_after_commands_not_executed_on_restore
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        after:
          - "echo 'Should not run on restore'"
        instances:
          lead:
            description: "Test instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    # Create a fake session path
    restore_path = File.join(@tmpdir, ".claude-swarm", "sessions", "test-session")
    FileUtils.mkdir_p(restore_path)

    generator.stub(:generate_all, nil) do
      orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, restore_session_path: restore_path)

      after_executed = false

      orchestrator.stub(:execute_after_commands?, lambda { |_commands, chdir:|
        _ = chdir # Mark as used for RuboCop
        after_executed = true
        true
      }) do
        orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
          block&.call(12345)
          true
        }) do
          orchestrator.stub(:cleanup_processes, nil) do
            orchestrator.stub(:cleanup_run_symlink, nil) do
              orchestrator.stub(:cleanup_worktrees, nil) do
                output = capture_io { orchestrator.start }[0]

                refute(after_executed, "After commands should not execute during session restoration")
                refute_match(/Executing after commands/, output)
              end
            end
          end
        end
      end
    end
  end

  def test_after_commands_execute_in_main_instance_directory
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        after:
          - "pwd > after_pwd.txt"
        instances:
          lead:
            description: "Test instance"
            directory: ./test_dir
    YAML

    test_dir = File.join(@tmpdir, "test_dir")
    FileUtils.mkdir_p(test_dir)

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    generator.stub(:generate_all, nil) do
      orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

      orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
        block&.call(12345)
        true
      }) do
        orchestrator.stub(:cleanup_processes, nil) do
          orchestrator.stub(:cleanup_run_symlink, nil) do
            orchestrator.stub(:cleanup_worktrees, nil) do
              capture_io { orchestrator.start }
            end
          end
        end
      end
    end

    # Verify the after command was executed in the main instance directory
    pwd_file = File.join(test_dir, "after_pwd.txt")

    assert_path_exists(pwd_file, "after_pwd.txt should be created in main instance directory")

    # Check that the recorded pwd matches the expected directory
    recorded_pwd = File.read(pwd_file).strip
    expected_pwd = File.expand_path(test_dir)
    # Normalize both paths to handle symlink resolution differences
    assert_equal(File.realpath(expected_pwd), File.realpath(recorded_pwd), "After commands should execute in main instance directory")
  end

  def test_after_commands_failure_still_performs_cleanup
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        after:
          - "exit 1"
        instances:
          lead:
            description: "Test instance"
            directory: .
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    generator.stub(:generate_all, nil) do
      orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

      system_called = false
      cleanup_processes_called = false
      cleanup_run_symlink_called = false
      cleanup_worktrees_called = false

      orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
        system_called = true
        block&.call(12345)
        true
      }) do
        orchestrator.stub(:cleanup_processes, lambda {
          cleanup_processes_called = true
        }) do
          orchestrator.stub(:cleanup_run_symlink, lambda {
            cleanup_run_symlink_called = true
          }) do
            orchestrator.stub(:cleanup_worktrees, lambda {
              cleanup_worktrees_called = true
            }) do
              output = capture_io { orchestrator.start }[0]

              # Verify warning message
              assert_match(/⚠️  Some after commands failed/, output)
            end
          end
        end
      end

      assert(system_called, "Main instance should be launched")
      assert(cleanup_processes_called, "cleanup_processes should be called even if after commands fail")
      assert(cleanup_run_symlink_called, "cleanup_run_symlink should be called even if after commands fail")
      assert(cleanup_worktrees_called, "cleanup_worktrees should be called even if after commands fail")
    end
  end

  def test_after_commands_with_empty_array
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        after: []
        instances:
          lead:
            description: "Test instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    generator.stub(:generate_all, nil) do
      orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

      after_executed = false

      orchestrator.stub(:execute_after_commands?, lambda { |_commands, chdir:|
        _ = chdir # Mark as used for RuboCop
        after_executed = true
        true
      }) do
        orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
          block&.call(12345)
          true
        }) do
          orchestrator.stub(:cleanup_processes, nil) do
            orchestrator.stub(:cleanup_run_symlink, nil) do
              orchestrator.stub(:cleanup_worktrees, nil) do
                output = capture_io { orchestrator.start }[0]

                refute(after_executed, "No commands should be executed with empty after array")
                refute_match(/Executing after commands/, output)
              end
            end
          end
        end
      end
    end
  end

  def test_after_commands_execute_on_signal_interruption
    skip("Signal handling test is not reliable in CI environment")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        after:
          - "echo 'Signal cleanup' > signal_cleanup.txt"
        instances:
          lead:
            description: "Test instance"
            directory: .
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    generator.stub(:generate_all, nil) do
      orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

      # Mock exit to prevent actual process termination
      exit_called = false
      orchestrator.stub(:exit, lambda { |_| exit_called = true }) do
        orchestrator.stub(:cleanup_all, nil) do
          # Track if cleanup block was called
          cleanup_called = false

          # Setup signal handler with a test block
          orchestrator.send(:setup_signal_handlers) do
            cleanup_called = true
            orchestrator.send(:cleanup_all)
            exit(0)
          end

          # Get the current handler and simulate calling it
          handler = Signal.trap("INT", "DEFAULT")
          Signal.trap("INT", handler)

          # Call the handler directly (safer than sending actual signal)
          capture_io do
            handler.call
          end

          assert(cleanup_called, "Cleanup block should be called")
        end
      end

      assert(exit_called, "Exit should be called after signal handling")
    end
  end

  def test_orchestrator_accepts_session_id_parameter
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)

    # Test that orchestrator accepts session_id parameter
    orchestrator = ClaudeSwarm::Orchestrator.new(
      config,
      generator,
      session_id: "my-custom-session-123",
    )

    assert_instance_of(ClaudeSwarm::Orchestrator, orchestrator)
  end

  def test_orchestrator_uses_provided_session_id
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    custom_session_id = "test-session-abc123"

    orchestrator = ClaudeSwarm::Orchestrator.new(
      config,
      generator,
      session_id: custom_session_id,
    )

    # Mock system to prevent actual execution
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Check that the session path contains our custom session ID
    session_path = ENV["CLAUDE_SWARM_SESSION_PATH"]

    assert(session_path)
    assert(session_path.end_with?(custom_session_id), "Session path should end with custom session ID")
  end

  def test_orchestrator_generates_uuid_when_no_session_id_provided
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)

    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    # Mock system to prevent actual execution
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Check that the session path contains a UUID
    session_path = ENV["CLAUDE_SWARM_SESSION_PATH"]

    assert(session_path)
    session_id = File.basename(session_path)

    assert_match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, session_id)
  end

  def test_session_id_with_worktree
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    custom_session_id = "worktree-session-999"

    # Mock WorktreeManager to prevent actual worktree operations
    mock_worktree_manager = Minitest::Mock.new
    mock_worktree_manager.expect(:setup_worktrees, nil, [Array])
    mock_worktree_manager.expect(:worktree_name, "feature-branch")
    mock_worktree_manager.expect(:session_metadata, { "enabled" => true, "shared_name" => "feature-branch" })
    mock_worktree_manager.expect(:cleanup_worktrees, nil)

    ClaudeSwarm::WorktreeManager.stub(:new, mock_worktree_manager) do
      orchestrator = ClaudeSwarm::Orchestrator.new(
        config,
        generator,
        session_id: custom_session_id,
        worktree: "feature-branch",
      )

      # Mock system to prevent actual execution
      orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
        block&.call(12345)
        true
      }) do
        capture_io { orchestrator.start }
      end

      # Verify session ID is used correctly even with worktree
      session_path = ENV["CLAUDE_SWARM_SESSION_PATH"]

      assert(session_path)
      assert(session_path.end_with?(custom_session_id), "Session path should end with custom session ID even with worktree")
    end

    mock_worktree_manager.verify
  end

  def test_session_id_saved_in_metadata
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    custom_session_id = "metadata-test-456"

    orchestrator = ClaudeSwarm::Orchestrator.new(
      config,
      generator,
      session_id: custom_session_id,
    )

    # Mock system to prevent actual execution
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Check metadata file contains the session ID
    session_path = ENV["CLAUDE_SWARM_SESSION_PATH"]
    metadata_file = File.join(session_path, "session_metadata.json")

    assert_path_exists(metadata_file)

    metadata = JSON.parse(File.read(metadata_file))

    # Should use config's base_dir, which is @tmpdir (where config file is)
    assert_equal(File.dirname(@config_path), metadata["root_directory"])
    assert_equal("Test Swarm", metadata["swarm_name"])
  end
end
