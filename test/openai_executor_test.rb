# frozen_string_literal: true

require "test_helper"

class OpenAIExecutorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @session_path = File.join(@tmpdir, "session-#{Time.now.to_i}")
    FileUtils.mkdir_p(@session_path)
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path

    # Mock OpenAI API key
    ENV["TEST_OPENAI_API_KEY"] = "test-key-123"
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
    ENV.delete("TEST_OPENAI_API_KEY")
  end

  def test_initialization_with_default_values
    executor = ClaudeSwarm::OpenAIExecutor.new(
      working_directory: @tmpdir,
      model: "gpt-4o",
      instance_name: "test-instance",
      instance_id: "test-123",
      openai_token_env: "TEST_OPENAI_API_KEY",
    )

    assert_equal(@tmpdir, executor.working_directory)
    assert_nil(executor.session_id)
    assert_equal(@session_path, executor.session_path)
  end

  def test_initialization_with_custom_values
    executor = ClaudeSwarm::OpenAIExecutor.new(
      working_directory: @tmpdir,
      model: "gpt-4",
      instance_name: "test-instance",
      instance_id: "test-123",
      temperature: 0.7,
      api_version: "responses",
      openai_token_env: "TEST_OPENAI_API_KEY",
      base_url: "https://custom.openai.com/v1",
    )

    assert_equal(@tmpdir, executor.working_directory)
  end

  def test_initialization_fails_without_api_key
    ENV.delete("TEST_OPENAI_API_KEY")

    assert_raises(ClaudeSwarm::OpenAIExecutor::ExecutionError) do
      ClaudeSwarm::OpenAIExecutor.new(
        working_directory: @tmpdir,
        model: "gpt-4o",
        instance_name: "test-instance",
        openai_token_env: "TEST_OPENAI_API_KEY",
      )
    end
  end

  def test_reset_session
    executor = ClaudeSwarm::OpenAIExecutor.new(
      working_directory: @tmpdir,
      model: "gpt-4o",
      instance_name: "test-instance",
      claude_session_id: "existing-session",
      openai_token_env: "TEST_OPENAI_API_KEY",
    )

    assert_predicate(executor, :has_session?)

    executor.reset_session

    refute_predicate(executor, :has_session?)
    assert_nil(executor.session_id)
  end

  def test_session_logging_setup
    ClaudeSwarm::OpenAIExecutor.new(
      working_directory: @tmpdir,
      model: "gpt-4o",
      instance_name: "test-instance",
      instance_id: "test-123",
      openai_token_env: "TEST_OPENAI_API_KEY",
    )

    # Check that log files are created
    log_file = File.join(@session_path, "session.log")
    File.join(@session_path, "session.log.json")

    assert_path_exists(log_file)

    # Verify log content
    log_content = File.read(log_file)

    assert_match(/Started OpenAI executor for instance: test-instance \(test-123\)/, log_content)
  end

  def test_mcp_config_loading
    # Create a mock MCP config file
    mcp_config_path = File.join(@tmpdir, "test.mcp.json")
    mcp_config = {
      "mcpServers" => {
        "test-server" => {
          "type" => "stdio",
          "command" => "echo",
          "args" => ["test"],
        },
      },
    }
    File.write(mcp_config_path, JSON.pretty_generate(mcp_config))

    # Skip actual MCP client creation for testing
    # In a real test, we'd mock the MCP client
    ClaudeSwarm::OpenAIExecutor.new(
      working_directory: @tmpdir,
      model: "gpt-4o",
      mcp_config: mcp_config_path,
      instance_name: "test-instance",
      openai_token_env: "TEST_OPENAI_API_KEY",
    )

    # The executor should attempt to load MCP config
    # In a real implementation, we'd verify MCP client was created
  end
end
