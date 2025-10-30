# frozen_string_literal: true

require "test_helper"

class ClaudeCodeExecutorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir

    # Set up session path for tests
    @session_path = File.join(@tmpdir, "test_session")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path

    @executor = ClaudeSwarm::ClaudeCodeExecutor.new(
      instance_name: "test_instance",
      calling_instance: "test_caller",
      debug: false,
    )
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  # Helper to create mock SDK messages
  def create_mock_messages(session_id: "test-session-123", result: "Test result", cost: 0.01, duration: 500, include_tool_call: false)
    messages = []

    # System init message
    system_msg = ClaudeSDK::Messages::System.new(
      subtype: "init",
      data: { session_id: session_id, tools: ["Tool1", "Tool2"] },
    )
    system_msg.define_singleton_method(:subtype) { "init" }
    system_msg.define_singleton_method(:session_id) { session_id }
    system_msg.define_singleton_method(:tools) { ["Tool1", "Tool2"] }
    messages << system_msg

    # Assistant message with content
    content = []
    content << ClaudeSDK::ContentBlock::Text.new(text: "Processing...")

    # Add tool call if requested
    if include_tool_call
      content << ClaudeSDK::ContentBlock::ToolUse.new(
        id: "tool_123",
        name: "Bash",
        input: { command: "ls -la" },
      )
    end

    # Assistant messages only have content attribute
    assistant_msg = ClaudeSDK::Messages::Assistant.new(content: content)
    messages << assistant_msg

    # Final assistant message with result text
    final_assistant_msg = ClaudeSDK::Messages::Assistant.new(
      content: [ClaudeSDK::ContentBlock::Text.new(text: result)],
    )
    messages << final_assistant_msg

    # Result message
    result_msg = ClaudeSDK::Messages::Result.new(
      subtype: "success",
      duration_ms: duration,
      duration_api_ms: (duration * 0.8).to_i,
      is_error: false,
      num_turns: 1,
      session_id: session_id,
      total_cost_usd: cost,
    )
    result_msg.define_singleton_method(:result) { result } # Result text is in message.result
    result_msg.define_singleton_method(:usage) { nil }

    messages << result_msg

    messages
  end

  # Helper to mock SDK query
  def mock_sdk_query(messages, &test_block)
    ClaudeSDK.stub(
      :query,
      proc { |_prompt, options: nil, &block| # rubocop:disable Lint/UnusedBlockArgument
        # Call the block with each message
        messages.each { |msg| block.call(msg) }
        nil # Return value doesn't matter when using a block
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
    session_path = ClaudeSwarm.joined_sessions_dir("test+project/20240102_123456")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path

    executor = ClaudeSwarm::ClaudeCodeExecutor.new(
      instance_name: "env_test",
      calling_instance: "env_caller",
      debug: false,
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
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(working_directory: custom_dir, debug: false)

    assert_equal(custom_dir, executor.working_directory)
  end

  def test_build_sdk_options_with_model
    # Ensure ANTHROPIC_MODEL is not set for this test
    original_env = ENV["ANTHROPIC_MODEL"]
    ENV.delete("ANTHROPIC_MODEL")

    executor = ClaudeSwarm::ClaudeCodeExecutor.new(model: "opus", debug: false)
    options = executor.send(:build_sdk_options, "test prompt", {})

    assert_equal("opus", options.model)
  ensure
    ENV["ANTHROPIC_MODEL"] = original_env if original_env
  end

  def test_build_sdk_options_with_settings_file
    Dir.mktmpdir do |tmpdir|
      # Set up session path
      ENV["CLAUDE_SWARM_SESSION_PATH"] = tmpdir

      # Create a settings file
      settings_file_path = File.join(tmpdir, "test_instance_settings.json")
      settings_content = {
        "hooks" => {
          "PreToolUse" => [
            {
              "matcher" => "Write",
              "hooks" => [
                {
                  "type" => "command",
                  "command" => "echo 'test hook'",
                },
              ],
            },
          ],
        },
      }
      File.write(settings_file_path, JSON.pretty_generate(settings_content))

      # Create executor with matching instance name
      executor = ClaudeSwarm::ClaudeCodeExecutor.new(
        instance_name: "test_instance",
        model: "opus",
        debug: false,
      )

      options = executor.send(:build_sdk_options, "test prompt", {})

      # Should have settings attribute set to the file path
      assert_equal(settings_file_path, options.settings)
    ensure
      ENV.delete("CLAUDE_SWARM_SESSION_PATH")
    end
  end

  def test_build_sdk_options_no_settings_when_file_missing
    Dir.mktmpdir do |tmpdir|
      ENV["CLAUDE_SWARM_SESSION_PATH"] = tmpdir

      # Create executor but don't create settings file
      executor = ClaudeSwarm::ClaudeCodeExecutor.new(
        instance_name: "test_instance",
        model: "opus",
        debug: false,
      )

      options = executor.send(:build_sdk_options, "test prompt", {})

      # Should not have settings attribute when file doesn't exist
      assert_nil(options.settings)
    ensure
      ENV.delete("CLAUDE_SWARM_SESSION_PATH")
    end
  end

  def test_build_sdk_options_with_mcp_config
    # Create a mock MCP config file
    mcp_config = {
      "mcpServers" => {
        "test_server" => {
          "type" => "stdio",
          "command" => "node",
          "args" => ["server.js"],
          "env" => { "KEY" => "value" },
        },
      },
    }
    config_path = File.join(@tmpdir, "mcp_config.json")
    File.write(config_path, JSON.pretty_generate(mcp_config))

    executor = ClaudeSwarm::ClaudeCodeExecutor.new(mcp_config: config_path, debug: false)
    options = executor.send(:build_sdk_options, "test prompt", {})

    assert_kind_of(Hash, options.mcp_servers)
    assert_includes(options.mcp_servers.keys, "test_server")
    server = options.mcp_servers["test_server"]

    assert_kind_of(ClaudeSDK::McpServerConfig::StdioServer, server)
    assert_equal("node", server.command)
    assert_equal(["server.js"], server.args)
    assert_equal({ "KEY" => "value" }, server.env)
  end

  def test_build_sdk_options_with_session
    @executor.instance_variable_set(:@session_id, "test-session-123")
    options = @executor.send(:build_sdk_options, "test prompt", {})

    assert_equal("test-session-123", options.resume)
  end

  def test_build_sdk_options_with_new_session_option
    @executor.instance_variable_set(:@session_id, "test-session-123")
    options = @executor.send(:build_sdk_options, "test prompt", { new_session: true })

    assert_nil(options.resume)
  end

  def test_build_sdk_options_with_system_prompt
    options = @executor.send(:build_sdk_options, "test prompt", { system_prompt: "You are a helpful assistant" })

    assert_equal("You are a helpful assistant", options.append_system_prompt)
  end

  def test_build_sdk_options_with_allowed_tools
    options = @executor.send(:build_sdk_options, "test prompt", { allowed_tools: ["Read", "Write", "Edit"] })

    assert_equal(["Read", "Write", "Edit"], options.allowed_tools)
  end

  def test_build_sdk_options_with_connections
    options = @executor.send(:build_sdk_options, "test prompt", {
      allowed_tools: ["Read", "Write"],
      connections: ["frontend", "backend"],
    })

    assert_equal(["Read", "Write", "mcp__frontend", "mcp__backend"], options.allowed_tools)
  end

  def test_execute_success
    mock_messages = create_mock_messages(
      session_id: "test-session-123",
      result: "Test result",
      cost: 0.01,
      duration: 500,
    )

    mock_sdk_query(mock_messages) do
      response = @executor.execute("test prompt", { system_prompt: "Be helpful" })

      assert_equal("Test result", response["result"])
      assert_equal("test-session-123", @executor.session_id)
      assert_in_delta(0.01, response["total_cost"])
      assert_equal(500, response["duration_ms"])
    end
  end

  def test_execute_error_handling
    # Mock SDK to raise an error
    ClaudeSDK.stub(
      :query,
      proc { |_prompt, _options: nil, &_block|
        raise StandardError, "SDK error"
      },
    ) do
      assert_raises(ClaudeSwarm::ClaudeCodeExecutor::ExecutionError) do
        @executor.execute("test prompt")
      end
    end
  end

  def test_execute_parse_error
    # Test when no result is found
    messages = create_mock_messages[0..1] # Only system and assistant messages, no result

    mock_sdk_query(messages) do
      assert_raises(ClaudeSwarm::ClaudeCodeExecutor::ParseError) do
        @executor.execute("test prompt")
      end
    end
  end

  def test_logging_on_successful_execution
    mock_messages = create_mock_messages(
      session_id: "test-session-123",
      result: "Test result",
      cost: 0.01,
      duration: 500,
    )

    mock_sdk_query(mock_messages) do
      response = @executor.execute("test prompt", { system_prompt: "Be helpful" })

      assert_equal("Test result", response["result"])
      assert_equal("test-session-123", @executor.session_id)
    end

    # Check log file
    log_path = File.join(@executor.session_path, "session.log")

    assert_path_exists(log_path, "Expected to find log file")

    log_content = File.read(log_path)

    # Check request logging
    assert_match(/test_caller -> test_instance:/, log_content)
    assert_match(/test prompt/, log_content)

    # Check response logging
    assert_match(/\(\$0.01 - 500ms\) test_instance -> test_caller:/, log_content)
    # The result text appears in the final result, which is logged between dashes
    # For now, let's just check that the response log format is correct
    assert_match(/test_instance -> test_caller:/, log_content)

    # Check assistant thinking log
    assert_match(/test_instance is thinking:/, log_content)
    assert_match(/Processing.../, log_content)

    # Check that the logger was started with instance name
    assert_match(/Started ClaudeSwarm::ClaudeCodeExecutor for instance: test_instance/, log_content)
  end

  def test_logging_with_tool_calls
    mock_messages = create_mock_messages(
      session_id: "test-session-123",
      result: "Command executed",
      include_tool_call: true,
    )

    mock_sdk_query(mock_messages) do
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
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(vibe: true, debug: false)
    options = executor.send(:build_sdk_options, "test prompt", {})

    assert_equal(ClaudeSDK::PermissionMode::BYPASS_PERMISSIONS, options.permission_mode)
  end

  def test_vibe_mode_overrides_allowed_tools
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(vibe: true, debug: false)
    options = executor.send(:build_sdk_options, "test prompt", { allowed_tools: ["Read", "Write"] })

    assert_equal(ClaudeSDK::PermissionMode::BYPASS_PERMISSIONS, options.permission_mode)
    # When vibe mode is enabled, allowed_tools is not set (remains default)
    # The SDK will ignore tool restrictions when permission_mode is BYPASS_PERMISSIONS
    assert_empty(options.allowed_tools || [])
  end

  def test_session_json_logging
    mock_messages = create_mock_messages

    mock_sdk_query(mock_messages) do
      @executor.execute("test prompt")
    end

    # Check session.log.json file
    json_path = File.join(@executor.session_path, "session.log.json")

    assert_path_exists(json_path, "Expected to find session JSON log file")

    # Read and parse each line
    entries = []
    File.foreach(json_path) do |line|
      entries << JSON.parse(line)
    end

    # Should have entries for request + each message
    assert_operator(entries.length, :>=, 4) # request + system + assistant + result

    # Check first entry is request
    assert_equal("request", entries.first["event"]["type"])
    assert_equal("test_caller", entries.first["event"]["from_instance"])
    assert_equal("test_instance", entries.first["event"]["to_instance"])

    # Check that we have system, assistant, and result events
    event_types = entries.map { |e| e["event"]["type"] }.uniq

    assert_includes(event_types, "system")
    assert_includes(event_types, "assistant")
    assert_includes(event_types, "result")
  end

  def test_additional_directories_warning
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(
      additional_directories: ["/path/to/dir1", "/path/to/dir2"],
      debug: false,
    )

    # Capture log output
    logger = executor.logger
    log_output = StringIO.new
    logger.instance_variable_set(:@logdev, Logger::LogDevice.new(log_output))

    executor.send(:build_sdk_options, "test prompt", {})

    # Check that warnings were logged
    log_content = log_output.string

    assert_match(/Additional directories not fully supported/, log_content)
    assert_match(%r{/path/to/dir1}, log_content)
  end

  def test_execute_with_nil_result
    # Create messages with nil result
    messages = []

    # System init message
    system_msg = ClaudeSDK::Messages::System.new(
      subtype: "init",
      data: { session_id: "test-session-123", tools: ["Tool1", "Tool2"] },
    )
    system_msg.define_singleton_method(:subtype) { "init" }
    system_msg.define_singleton_method(:session_id) { "test-session-123" }
    system_msg.define_singleton_method(:tools) { ["Tool1", "Tool2"] }
    messages << system_msg

    # Assistant message
    assistant_msg = ClaudeSDK::Messages::Assistant.new(
      content: [ClaudeSDK::ContentBlock::Text.new(text: "Processing...")],
    )
    messages << assistant_msg

    # Result message with nil result
    result_msg = ClaudeSDK::Messages::Result.new(
      subtype: "success",
      duration_ms: 500,
      duration_api_ms: 400,
      is_error: false,
      num_turns: 1,
      session_id: "test-session-123",
      total_cost_usd: 0.01,
    )
    result_msg.define_singleton_method(:result) { nil }
    result_msg.define_singleton_method(:usage) { nil }
    messages << result_msg

    mock_sdk_query(messages) do
      error = assert_raises(ClaudeSwarm::ClaudeCodeExecutor::ExecutionError) do
        @executor.execute("test prompt")
      end

      assert_equal("Claude Code execution failed: Claude SDK returned an empty result. The agent completed execution but provided no response content.", error.message)
    end
  end

  def test_execute_with_empty_string_result
    # Create messages with empty string result
    messages = []

    # System init message
    system_msg = ClaudeSDK::Messages::System.new(
      subtype: "init",
      data: { session_id: "test-session-123", tools: ["Tool1", "Tool2"] },
    )
    system_msg.define_singleton_method(:subtype) { "init" }
    system_msg.define_singleton_method(:session_id) { "test-session-123" }
    system_msg.define_singleton_method(:tools) { ["Tool1", "Tool2"] }
    messages << system_msg

    # Assistant message
    assistant_msg = ClaudeSDK::Messages::Assistant.new(
      content: [ClaudeSDK::ContentBlock::Text.new(text: "Processing...")],
    )
    messages << assistant_msg

    # Result message with empty string result
    result_msg = ClaudeSDK::Messages::Result.new(
      subtype: "success",
      duration_ms: 500,
      duration_api_ms: 400,
      is_error: false,
      num_turns: 1,
      session_id: "test-session-123",
      total_cost_usd: 0.01,
    )
    result_msg.define_singleton_method(:result) { "" }
    result_msg.define_singleton_method(:usage) { nil }
    messages << result_msg

    mock_sdk_query(messages) do
      error = assert_raises(ClaudeSwarm::ClaudeCodeExecutor::ExecutionError) do
        @executor.execute("test prompt")
      end

      assert_equal("Claude Code execution failed: Claude SDK returned an empty result. The agent completed execution but provided no response content.", error.message)
    end
  end

  def test_execute_with_whitespace_only_result
    # Create messages with whitespace-only result
    messages = []

    # System init message
    system_msg = ClaudeSDK::Messages::System.new(
      subtype: "init",
      data: { session_id: "test-session-123", tools: ["Tool1", "Tool2"] },
    )
    system_msg.define_singleton_method(:subtype) { "init" }
    system_msg.define_singleton_method(:session_id) { "test-session-123" }
    system_msg.define_singleton_method(:tools) { ["Tool1", "Tool2"] }
    messages << system_msg

    # Assistant message
    assistant_msg = ClaudeSDK::Messages::Assistant.new(
      content: [ClaudeSDK::ContentBlock::Text.new(text: "Processing...")],
    )
    messages << assistant_msg

    # Result message with whitespace-only result
    result_msg = ClaudeSDK::Messages::Result.new(
      subtype: "success",
      duration_ms: 500,
      duration_api_ms: 400,
      is_error: false,
      num_turns: 1,
      session_id: "test-session-123",
      total_cost_usd: 0.01,
    )
    result_msg.define_singleton_method(:result) { "   \n\t  " }
    result_msg.define_singleton_method(:usage) { nil }
    messages << result_msg

    mock_sdk_query(messages) do
      error = assert_raises(ClaudeSwarm::ClaudeCodeExecutor::ExecutionError) do
        @executor.execute("test prompt")
      end

      assert_equal("Claude Code execution failed: Claude SDK returned an empty result. The agent completed execution but provided no response content.", error.message)
    end
  end

  def test_execute_with_valid_result_containing_whitespace
    # Test that valid results with whitespace are not rejected
    messages = []

    # System init message
    system_msg = ClaudeSDK::Messages::System.new(
      subtype: "init",
      data: { session_id: "test-session-123", tools: ["Tool1", "Tool2"] },
    )
    system_msg.define_singleton_method(:subtype) { "init" }
    system_msg.define_singleton_method(:session_id) { "test-session-123" }
    system_msg.define_singleton_method(:tools) { ["Tool1", "Tool2"] }
    messages << system_msg

    # Assistant message
    assistant_msg = ClaudeSDK::Messages::Assistant.new(
      content: [ClaudeSDK::ContentBlock::Text.new(text: "Processing...")],
    )
    messages << assistant_msg

    # Result message with valid result containing leading/trailing whitespace
    result_msg = ClaudeSDK::Messages::Result.new(
      subtype: "success",
      duration_ms: 500,
      duration_api_ms: 400,
      is_error: false,
      num_turns: 1,
      session_id: "test-session-123",
      total_cost_usd: 0.01,
    )
    result_msg.define_singleton_method(:result) { "  Valid result with whitespace  " }
    result_msg.define_singleton_method(:usage) { nil }
    messages << result_msg

    mock_sdk_query(messages) do
      response = @executor.execute("test prompt")

      # Should not raise an error and should return the result with whitespace preserved
      assert_equal("  Valid result with whitespace  ", response["result"])
      assert_equal("test-session-123", response["session_id"])
      assert_in_delta(0.01, response["total_cost"])
    end
  end
end
