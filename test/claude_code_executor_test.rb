# frozen_string_literal: true

require "test_helper"

class ClaudeCodeExecutorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@tmpdir)

    # Set up session path for tests
    @session_path = File.join(@tmpdir, "test_session")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path

    @executor = ClaudeSwarm::ClaudeCodeExecutor.new(
      instance_name: "test_instance",
      calling_instance: "test_caller",
    )
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  # Helper method to create streaming JSON output
  def create_streaming_json(session_id: "test-session-123", result: "Test result", cost: 0.01, duration: 500, include_tool_call: false)
    events = [
      { type: "system", subtype: "init", session_id: session_id, tools: ["Tool1", "Tool2"] },
      {
        type: "assistant",
        message: {
          id: "msg_123",
          type: "message",
          role: "assistant",
          model: "claude-3",
          content: [{ type: "text", text: "Processing..." }],
        },
        session_id: session_id,
      },
    ]

    if include_tool_call
      events << {
        type: "assistant",
        message: {
          id: "msg_124",
          type: "message",
          role: "assistant",
          model: "claude-3",
          content: [
            { type: "tool_use", id: "tool_123", name: "Bash", input: { command: "ls -la" } },
          ],
        },
        session_id: session_id,
      }
    end

    events << {
      type: "result",
      subtype: "success",
      cost_usd: cost,
      is_error: false,
      duration_ms: duration,
      result: result,
      total_cost: cost,
      session_id: session_id,
    }

    events.map { |obj| "#{JSON.generate(obj)}\n" }.join
  end

  # Helper to mock popen3
  def mock_popen3(stdout_content, stderr_content = "", success: true, &test_block)
    Open3.stub(
      :popen3,
      proc { |*_args, **_opts, &block|
        stdin_mock = StringIO.new
        stdout_mock = StringIO.new(stdout_content)
        stderr_mock = StringIO.new(stderr_content)

        wait_thread_stub = Object.new
        wait_thread_stub.define_singleton_method(:value) do
          status_stub = Object.new
          status_stub.define_singleton_method(:success?) { success }
          status_stub
        end

        # Call the block that popen3 would call
        block.call(stdin_mock, stdout_mock, stderr_mock, wait_thread_stub)
      },
      &test_block
    )
  end

  def test_initialization
    assert_nil(@executor.session_id)
    assert_nil(@executor.last_response)
    assert_equal(Dir.pwd, @executor.working_directory)
    assert_kind_of(Logger, @executor.logger)
    assert_equal(@session_path, @executor.session_path)
  end

  def test_initialization_with_environment_session_path
    # Set environment variable
    session_path = File.join(ClaudeSwarm::SessionPath.swarm_home, "sessions/test+project/20240102_123456")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path

    executor = ClaudeSwarm::ClaudeCodeExecutor.new(
      instance_name: "env_test",
      calling_instance: "env_caller",
    )

    assert_equal(session_path, executor.session_path)

    # Check that the log file is created in the correct directory
    log_path = File.join(session_path, "session.log")

    assert_path_exists(log_path, "Expected log file to exist at #{log_path}")
  ensure
    # Clean up environment variable
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def test_has_session
    refute_predicate(@executor, :has_session?)

    # Simulate setting a session ID
    @executor.instance_variable_set(:@session_id, "test-session-123")

    assert_predicate(@executor, :has_session?)
  end

  def test_reset_session
    # Set some values
    @executor.instance_variable_set(:@session_id, "test-session-123")
    @executor.instance_variable_set(:@last_response, { "test" => "data" })

    @executor.reset_session

    assert_nil(@executor.session_id)
    assert_nil(@executor.last_response)
  end

  def test_custom_working_directory
    custom_dir = "/tmp"
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(working_directory: custom_dir)

    assert_equal(custom_dir, executor.working_directory)
  end

  def test_custom_model
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(model: "opus")
    command_array = executor.send(:build_command_array, "test prompt", {})

    assert_includes(command_array, "--model")
    assert_includes(command_array, "opus")
    assert_includes(command_array, "--verbose")
  end

  def test_mcp_config
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(mcp_config: "/path/to/config.json")
    command_array = executor.send(:build_command_array, "test prompt", {})

    assert_includes(command_array, "--mcp-config")
    assert_includes(command_array, "/path/to/config.json")
  end

  def test_build_command_with_session
    @executor.instance_variable_set(:@session_id, "test-session-123")
    command_array = @executor.send(:build_command_array, "test prompt", {})

    assert_includes(command_array, "--resume")
    assert_includes(command_array, "test-session-123")
    assert_includes(command_array, "--output-format")
    assert_includes(command_array, "stream-json")
    assert_includes(command_array, "--print")
    assert_includes(command_array, "--verbose")
    assert_includes(command_array, "test prompt") # No escaping in array
  end

  def test_build_command_with_new_session_option
    @executor.instance_variable_set(:@session_id, "test-session-123")
    command_array = @executor.send(:build_command_array, "test prompt", { new_session: true })

    refute_includes(command_array, "--resume")
  end

  def test_build_command_with_system_prompt
    command_array = @executor.send(:build_command_array, "test prompt", { system_prompt: "You are a helpful assistant" })

    assert_includes(command_array, "--append-system-prompt")
    assert_includes(command_array, "You are a helpful assistant")
  end

  def test_build_command_with_allowed_tools
    command_array = @executor.send(:build_command_array, "test prompt", { allowed_tools: ["Read", "Write", "Edit"] })

    assert_includes(command_array, "--allowedTools")
    assert_includes(command_array, "Read,Write,Edit")
  end

  def test_execute_error_handling
    mock_popen3("", "Error message", success: false) do
      assert_raises(ClaudeSwarm::ClaudeCodeExecutor::ExecutionError) do
        @executor.execute("test prompt")
      end
    end
  end

  def test_execute_parse_error
    # Test when no result is found in stream
    incomplete_json = [
      { type: "system", subtype: "init", session_id: "test-123" },
      { type: "assistant", message: { content: [{ type: "text", text: "Hi" }] }, session_id: "test-123" },
    ].map { |obj| "#{JSON.generate(obj)}\n" }.join

    mock_popen3(incomplete_json) do
      assert_raises(ClaudeSwarm::ClaudeCodeExecutor::ParseError) do
        @executor.execute("test prompt")
      end
    end
  end

  def test_logging_on_successful_execution
    mock_response = create_streaming_json(
      session_id: "test-session-123",
      result: "Test result",
      cost: 0.01,
      duration: 500,
    )

    mock_popen3(mock_response) do
      response = @executor.execute("test prompt", { system_prompt: "Be helpful" })

      assert_equal("Test result", response["result"])
      assert_equal("test-session-123", @executor.session_id)
    end

    # Check log file in new location
    log_path = File.join(@executor.session_path, "session.log")

    assert_path_exists(log_path, "Expected to find log file")

    log_content = File.read(log_path)

    # Check request logging - new format: "calling_instance -> instance_name:"
    assert_match(/test_caller -> test_instance:/, log_content)
    assert_match(/test prompt/, log_content)

    # Check response logging - new format: "($cost - timems) instance_name -> calling_instance:"
    assert_match(/\(\$0.01 - 500ms\) test_instance -> test_caller:/, log_content)
    assert_match(/Test result/, log_content)

    # Check assistant thinking log
    assert_match(/test_instance is thinking:/, log_content)
    assert_match(/Processing.../, log_content)

    # Check that the logger was started with instance name
    assert_match(/Started Claude Code executor for instance: test_instance/, log_content)
  end

  def test_logging_on_execution_error
    mock_popen3("", "Command failed", success: false) do
      assert_raises(ClaudeSwarm::ClaudeCodeExecutor::ExecutionError) do
        @executor.execute("test prompt")
      end
    end

    # Check log file for error
    log_path = File.join(@executor.session_path, "session.log")

    assert_path_exists(log_path, "Expected to find log file")

    log_content = File.read(log_path)

    assert_match(/ERROR.*Execution error for test_instance: Command failed/, log_content)
  end

  def test_logging_with_tool_calls
    mock_response = create_streaming_json(
      session_id: "test-session-123",
      result: "Command executed",
      include_tool_call: true,
    )

    mock_popen3(mock_response) do
      response = @executor.execute("run ls command")

      assert_equal("Command executed", response["result"])
    end

    # Check log file for tool call
    log_path = File.join(@executor.session_path, "session.log")
    log_content = File.read(log_path)

    # Check tool call logging
    assert_match(/Tool call from test_instance -> Tool: Bash, ID: tool_123, Arguments: {"command":"ls -la"}/, log_content)
  end

  def test_vibe_mode
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(vibe: true)
    command_array = executor.send(:build_command_array, "test prompt", {})

    assert_includes(command_array, "--dangerously-skip-permissions")
    refute_includes(command_array, "--allowedTools")
  end

  def test_vibe_mode_overrides_allowed_tools
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(vibe: true)
    command_array = executor.send(:build_command_array, "test prompt", { allowed_tools: ["Read", "Write"] })

    assert_includes(command_array, "--dangerously-skip-permissions")
    refute_includes(command_array, "--allowedTools")
  end
end
