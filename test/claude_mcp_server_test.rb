# frozen_string_literal: true

require "test_helper"

class ClaudeMcpServerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@tmpdir)

    @instance_config = {
      name: "test_instance",
      directory: @tmpdir,
      directories: [@tmpdir],
      model: "sonnet",
      prompt: "Test prompt",
      allowed_tools: ["Read", "Edit"],
      mcp_config_path: nil,
    }

    # Reset class variables
    ClaudeSwarm::ClaudeMcpServer.executor = nil
    ClaudeSwarm::ClaudeMcpServer.instance_config = nil
    ClaudeSwarm::ClaudeMcpServer.logger = nil
    ClaudeSwarm::ClaudeMcpServer.session_path = nil
    ClaudeSwarm::ClaudeMcpServer.calling_instance_id = nil

    # Set up session path for tests
    @session_path = File.join(@tmpdir, "test_session")
    @original_env = ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil)
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path

    # Store original tool descriptions
    @original_task_description = ClaudeSwarm::Tools::TaskTool.description
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @original_env if @original_env

    # Reset TaskTool description to original
    ClaudeSwarm::Tools::TaskTool.description(@original_task_description)
  end

  def test_initialization
    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    # Check class variables are set
    assert(ClaudeSwarm::ClaudeMcpServer.executor)
    assert_equal(@instance_config, ClaudeSwarm::ClaudeMcpServer.instance_config)
    assert(ClaudeSwarm::ClaudeMcpServer.logger)
  end

  def test_initialization_with_calling_instance_id
    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller", calling_instance_id: "test_caller_1234abcd")

    # Check class variables are set
    assert(ClaudeSwarm::ClaudeMcpServer.executor)
    assert_equal(@instance_config, ClaudeSwarm::ClaudeMcpServer.instance_config)
    assert(ClaudeSwarm::ClaudeMcpServer.logger)
    assert_equal("test_caller_1234abcd", ClaudeSwarm::ClaudeMcpServer.calling_instance_id)
  end

  def test_logging_with_environment_session_path
    session_path = File.join(ClaudeSwarm::SessionPath.swarm_home, "sessions/test+project/20240101_120000")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path

    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    assert_equal(session_path, ClaudeSwarm::ClaudeMcpServer.session_path)

    log_file = File.join(session_path, "session.log")

    assert_path_exists(log_file)

    log_content = File.read(log_file)

    assert_match(/Started Claude Code executor for instance: test_instance/, log_content)
  end

  def test_logging_without_environment_session_path
    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    session_path = ClaudeSwarm::ClaudeMcpServer.session_path

    assert_equal(@session_path, session_path)

    log_file = File.join(session_path, "session.log")

    assert_path_exists(log_file)
  end

  def test_start_method
    server = ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    # Mock FastMcp::Server
    mock_server = Minitest::Mock.new
    mock_server.expect(:register_tool, nil, [ClaudeSwarm::Tools::TaskTool])
    mock_server.expect(:register_tool, nil, [ClaudeSwarm::Tools::SessionInfoTool])
    mock_server.expect(:register_tool, nil, [ClaudeSwarm::Tools::ResetSessionTool])
    mock_server.expect(:start, nil)

    FastMcp::Server.stub(:new, mock_server) do
      server.start
    end

    mock_server.verify
  end

  def test_task_tool_basic
    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    # Mock executor
    mock_executor = Minitest::Mock.new
    mock_executor.expect(
      :execute,
      {
        "result" => "Task completed successfully",
        "cost_usd" => 0.01,
        "duration_ms" => 1000,
        "is_error" => false,
        "total_cost" => 0.01,
      },
      ["Test task", { new_session: false, system_prompt: "Test prompt", description: nil, allowed_tools: ["Read", "Edit"] }],
    )

    ClaudeSwarm::ClaudeMcpServer.executor = mock_executor

    tool = ClaudeSwarm::Tools::TaskTool.new
    result = tool.call(prompt: "Test task")

    assert_equal("Task completed successfully", result)
    mock_executor.verify
  end

  def test_task_tool_with_new_session
    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    mock_executor = Minitest::Mock.new
    mock_executor.expect(
      :execute,
      {
        "result" => "New session started",
        "cost_usd" => 0.02,
        "duration_ms" => 1500,
        "is_error" => false,
        "total_cost" => 0.02,
      },
      ["Start fresh", { new_session: true, system_prompt: "Test prompt", description: nil, allowed_tools: ["Read", "Edit"] }],
    )

    ClaudeSwarm::ClaudeMcpServer.executor = mock_executor

    tool = ClaudeSwarm::Tools::TaskTool.new
    result = tool.call(prompt: "Start fresh", new_session: true)

    assert_equal("New session started", result)
    mock_executor.verify
  end

  def test_task_tool_with_custom_system_prompt
    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    mock_executor = Minitest::Mock.new
    mock_executor.expect(
      :execute,
      {
        "result" => "Custom prompt used",
        "cost_usd" => 0.01,
        "duration_ms" => 800,
        "is_error" => false,
        "total_cost" => 0.01,
      },
      ["Do something", { new_session: false, system_prompt: "Custom prompt", description: nil, allowed_tools: ["Read", "Edit"] }],
    )

    ClaudeSwarm::ClaudeMcpServer.executor = mock_executor

    tool = ClaudeSwarm::Tools::TaskTool.new
    result = tool.call(prompt: "Do something", system_prompt: "Custom prompt")

    assert_equal("Custom prompt used", result)
    mock_executor.verify
  end

  def test_task_tool_logging
    # Since logging is now done in ClaudeCodeExecutor, we need to test through a real instance
    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    # Create streaming JSON response
    streaming_json = [
      { type: "system", subtype: "init", session_id: "test-session-1", tools: ["Tool1"] },
      {
        type: "assistant",
        message: { id: "msg_1", content: [{ type: "text", text: "Working..." }] },
        session_id: "test-session-1",
      },
      {
        type: "result",
        subtype: "success",
        result: "Logged task",
        cost_usd: 0.01,
        duration_ms: 500,
        is_error: false,
        total_cost: 0.01,
        session_id: "test-session-1",
      },
    ].map { |obj| "#{JSON.generate(obj)}\n" }.join

    # Mock popen3 for streaming
    stdin_mock = StringIO.new
    stdout_mock = StringIO.new(streaming_json)
    stderr_mock = StringIO.new("")

    wait_thread_stub = Object.new
    wait_thread_stub.define_singleton_method(:value) do
      status_stub = Object.new
      status_stub.define_singleton_method(:success?) { true }
      status_stub
    end

    Open3.stub(:popen3, proc { |*_args, **_opts, &block|
      block.call(stdin_mock, stdout_mock, stderr_mock, wait_thread_stub)
    }) do
      tool = ClaudeSwarm::Tools::TaskTool.new
      result = tool.call(prompt: "Log this task")

      assert_equal("Logged task", result)
    end

    # Check log file
    log_files = find_log_files

    assert_predicate(log_files, :any?, "Expected to find log files")
    log_content = File.read(log_files.first)

    # Check for the new logging format
    assert_match(/test_caller -> test_instance:/, log_content)
    assert_match(/Log this task/, log_content)
    assert_match(/test_instance -> test_caller:/, log_content)
    assert_match(/Logged task/, log_content)
    assert_match(/\$0\.01 - 500ms/, log_content)
  end

  def test_session_info_tool
    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    mock_executor = Minitest::Mock.new
    mock_executor.expect(:has_session?, true)
    mock_executor.expect(:session_id, "test-session-123")
    mock_executor.expect(:working_directory, "/test/dir")

    ClaudeSwarm::ClaudeMcpServer.executor = mock_executor

    tool = ClaudeSwarm::Tools::SessionInfoTool.new
    result = tool.call

    assert_equal(
      {
        has_session: true,
        session_id: "test-session-123",
        working_directory: "/test/dir",
      },
      result,
    )

    mock_executor.verify
  end

  def test_reset_session_tool
    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    mock_executor = Minitest::Mock.new
    mock_executor.expect(:reset_session, nil)

    ClaudeSwarm::ClaudeMcpServer.executor = mock_executor

    tool = ClaudeSwarm::Tools::ResetSessionTool.new
    result = tool.call

    assert_equal(
      {
        success: true,
        message: "Session has been reset",
      },
      result,
    )

    mock_executor.verify
  end

  def test_instance_config_without_tools
    config = @instance_config.dup
    config[:allowed_tools] = nil

    ClaudeSwarm::ClaudeMcpServer.new(config, calling_instance: "test_caller")

    mock_executor = Minitest::Mock.new
    mock_executor.expect(
      :execute,
      {
        "result" => "No tools specified",
        "cost_usd" => 0.01,
        "duration_ms" => 500,
        "is_error" => false,
        "total_cost" => 0.01,
      },
      ["Test", { new_session: false, system_prompt: "Test prompt", description: nil }],
    ) # No allowed_tools

    ClaudeSwarm::ClaudeMcpServer.executor = mock_executor

    tool = ClaudeSwarm::Tools::TaskTool.new
    result = tool.call(prompt: "Test")

    assert_equal("No tools specified", result)
    mock_executor.verify
  end

  def test_tool_descriptions
    assert_equal("Execute a task using Claude Code. There is no description parameter.", ClaudeSwarm::Tools::TaskTool.description)
    assert_equal("Get information about the current Claude session for this agent", ClaudeSwarm::Tools::SessionInfoTool.description)
    assert_equal(
      "Reset the Claude session for this agent, starting fresh on the next task",
      ClaudeSwarm::Tools::ResetSessionTool.description,
    )
  end

  def test_tool_names
    assert_equal("task", ClaudeSwarm::Tools::TaskTool.tool_name)
    assert_equal("session_info", ClaudeSwarm::Tools::SessionInfoTool.tool_name)
    assert_equal("reset_session", ClaudeSwarm::Tools::ResetSessionTool.tool_name)
  end

  def test_server_with_openai_provider
    # Mock OpenAI API key
    ENV["TEST_OPENAI_API_KEY"] = "test-key-123"

    openai_config = @instance_config.merge(
      provider: "openai",
      temperature: 0.7,
      api_version: "chat_completion",
      openai_token_env: "TEST_OPENAI_API_KEY",
      base_url: "https://custom.openai.com/v1",
    )

    ClaudeSwarm::ClaudeMcpServer.new(openai_config, calling_instance: "test_caller")

    # Verify that OpenAIExecutor was created
    executor = ClaudeSwarm::ClaudeMcpServer.executor

    assert_kind_of(ClaudeSwarm::OpenAIExecutor, executor)
    assert_equal(@tmpdir, executor.working_directory)
  ensure
    ENV.delete("TEST_OPENAI_API_KEY")
  end

  def test_server_with_claude_provider_default
    ClaudeSwarm::ClaudeMcpServer.new(@instance_config, calling_instance: "test_caller")

    # Verify that ClaudeCodeExecutor was created (default)
    executor = ClaudeSwarm::ClaudeMcpServer.executor

    assert_kind_of(ClaudeSwarm::ClaudeCodeExecutor, executor)
    assert_equal(@tmpdir, executor.working_directory)
  end

  def test_server_with_explicit_claude_provider
    claude_config = @instance_config.merge(provider: "claude")

    ClaudeSwarm::ClaudeMcpServer.new(claude_config, calling_instance: "test_caller")

    # Verify that ClaudeCodeExecutor was created
    executor = ClaudeSwarm::ClaudeMcpServer.executor

    assert_kind_of(ClaudeSwarm::ClaudeCodeExecutor, executor)
  end

  def test_openai_executor_receives_all_parameters
    ENV["TEST_OPENAI_API_KEY"] = "test-key-123"

    openai_config = @instance_config.merge(
      provider: "openai",
      temperature: 0.5,
      api_version: "responses",
      openai_token_env: "TEST_OPENAI_API_KEY",
      base_url: "https://api.openai.com/v1",
      vibe: true,
    )

    # We can't easily test all internal parameters without exposing them,
    # but we can verify the executor is created successfully
    ClaudeSwarm::ClaudeMcpServer.new(openai_config, calling_instance: "test_caller", calling_instance_id: "caller-123")

    executor = ClaudeSwarm::ClaudeMcpServer.executor

    assert_kind_of(ClaudeSwarm::OpenAIExecutor, executor)

    # Verify class variables are set correctly
    assert_equal(openai_config, ClaudeSwarm::ClaudeMcpServer.instance_config)
    assert_equal("test_caller", ClaudeSwarm::ClaudeMcpServer.calling_instance)
    assert_equal("caller-123", ClaudeSwarm::ClaudeMcpServer.calling_instance_id)
  ensure
    ENV.delete("TEST_OPENAI_API_KEY")
  end
end
