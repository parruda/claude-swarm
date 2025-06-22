# frozen_string_literal: true

require "test_helper"

class ExecutorFactoryTest < Minitest::Test
  def setup
    @session_path = Dir.mktmpdir
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path
  end

  def teardown
    FileUtils.rm_rf(@session_path)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def test_create_with_anthropic_provider
    instance_config = {
      name: "test_instance",
      instance_id: "test_123",
      directory: "/tmp/test",
      model: "claude-3-sonnet",
      mcp_config_path: "/tmp/mcp.json",
      vibe: false,
      claude_session_id: "test_session",
      directories: ["/tmp/test", "/tmp/other"],
      provider: "anthropic"
    }

    executor = ClaudeSwarm::ExecutorFactory.create(
      instance_config,
      calling_instance: "caller",
      calling_instance_id: "caller_123"
    )

    assert_instance_of ClaudeSwarm::ClaudeCodeExecutor, executor
    assert_equal "/tmp/test", executor.working_directory
  end

  def test_create_with_default_provider
    instance_config = {
      name: "test_instance",
      instance_id: "test_123",
      directory: "/tmp/test",
      model: "claude-3-sonnet",
      directories: ["/tmp/test"]
    }

    executor = ClaudeSwarm::ExecutorFactory.create(
      instance_config,
      calling_instance: "caller"
    )

    assert_instance_of ClaudeSwarm::ClaudeCodeExecutor, executor
  end

  def test_create_with_non_anthropic_provider_without_support
    instance_config = {
      name: "test_instance",
      instance_id: "test_123",
      directory: "/tmp/test",
      model: "gpt-4",
      provider: "openai"
    }

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::ExecutorFactory.create(
        instance_config,
        calling_instance: "caller"
      )
    end

    assert_match(/Multi-provider support is not available/, error.message)
    assert_match(/gem install claude-swarm-providers/, error.message)
  end

  def test_create_with_non_anthropic_provider_with_support
    # Skip if Providers module already exists (it will in the full test suite)
    skip "Skipping test as Providers module is already loaded" if defined?(ClaudeSwarm::Providers)

    # Mock the presence of provider support
    ClaudeSwarm.const_set(:Providers, Module.new)
    mock_llm_executor = Object.new
    ClaudeSwarm::Providers.const_set(:LlmExecutor, Class.new)

    # Capture the arguments passed to LlmExecutor.new
    called_with = nil

    ClaudeSwarm::Providers::LlmExecutor.stub :new, lambda { |args|
      called_with = args
      mock_llm_executor
    } do
      instance_config = {
        name: "test_instance",
        instance_id: "test_123",
        directory: "/tmp/test",
        model: "gpt-4",
        provider: "openai",
        api_key_env: "OPENAI_API_KEY",
        api_base_env: "OPENAI_BASE_URL",
        assume_model_exists: true,
        mcp_config_path: "/tmp/mcp.json",
        vibe: true,
        directories: ["/tmp/test", "/tmp/other"]
      }

      executor = ClaudeSwarm::ExecutorFactory.create(
        instance_config,
        calling_instance: "caller",
        calling_instance_id: "caller_123"
      )

      assert_equal mock_llm_executor, executor
    end

    # Verify the correct parameters were passed
    assert_equal "openai", called_with[:provider]
    assert_equal "gpt-4", called_with[:model]
    assert_equal "OPENAI_API_KEY", called_with[:api_key_env]
    assert_equal "OPENAI_BASE_URL", called_with[:api_base_env]
    assert called_with[:assume_model_exists]
    assert_equal "/tmp/mcp.json", called_with[:mcp_config]
    assert called_with[:vibe]
    assert_equal ["/tmp/other"], called_with[:additional_directories]
    assert_equal "/tmp/test", called_with[:working_directory]
    assert_equal "test_instance", called_with[:instance_name]
    assert_equal "test_123", called_with[:instance_id]
    assert_equal "caller", called_with[:calling_instance]
    assert_equal "caller_123", called_with[:calling_instance_id]
  ensure
    # Clean up the mocked module only if we created it
    ClaudeSwarm.send(:remove_const, :Providers) if defined?(ClaudeSwarm::Providers::LlmExecutor)
  end

  def test_create_passes_correct_parameters_to_claude_executor
    instance_config = {
      name: "test_instance",
      instance_id: "test_123",
      directory: "/tmp/test",
      model: "claude-3-opus",
      mcp_config_path: "/tmp/mcp.json",
      vibe: true,
      claude_session_id: "session_123",
      directories: ["/tmp/test", "/tmp/dir1", "/tmp/dir2"],
      provider: "anthropic"
    }

    # Capture the arguments passed to ClaudeCodeExecutor.new
    called_with = nil
    mock_executor = Object.new

    ClaudeSwarm::ClaudeCodeExecutor.stub :new, lambda { |args|
      called_with = args
      mock_executor
    } do
      result = ClaudeSwarm::ExecutorFactory.create(
        instance_config,
        calling_instance: "caller",
        calling_instance_id: "caller_123"
      )

      assert_equal mock_executor, result
    end

    # Verify the correct parameters were passed
    assert_equal "/tmp/test", called_with[:working_directory]
    assert_equal "test_instance", called_with[:instance_name]
    assert_equal "test_123", called_with[:instance_id]
    assert_equal "caller", called_with[:calling_instance]
    assert_equal "caller_123", called_with[:calling_instance_id]
    assert_equal "claude-3-opus", called_with[:model]
    assert_equal "/tmp/mcp.json", called_with[:mcp_config]
    assert called_with[:vibe]
    assert_equal "session_123", called_with[:claude_session_id]
    assert_equal ["/tmp/dir1", "/tmp/dir2"], called_with[:additional_directories]
  end

  def test_create_handles_empty_directories_array
    instance_config = {
      name: "test_instance",
      directory: "/tmp/test",
      model: "claude-3-sonnet",
      directories: []
    }

    executor = ClaudeSwarm::ExecutorFactory.create(
      instance_config,
      calling_instance: "caller"
    )

    assert_instance_of ClaudeSwarm::ClaudeCodeExecutor, executor
  end

  def test_create_handles_nil_directories
    instance_config = {
      name: "test_instance",
      directory: "/tmp/test",
      model: "claude-3-sonnet"
    }

    executor = ClaudeSwarm::ExecutorFactory.create(
      instance_config,
      calling_instance: "caller"
    )

    assert_instance_of ClaudeSwarm::ClaudeCodeExecutor, executor
  end
end
