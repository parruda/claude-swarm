# frozen_string_literal: true

require "test_helper"

class ProvidersLlmExecutorTest < Minitest::Test
  def setup
    skip_unless_ruby_llm_available

    @session_path = Dir.mktmpdir
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path
    ENV["OPENAI_API_KEY"] = "test-key"
    ENV["GOOGLE_API_KEY"] = "test-google-key"
  end

  def teardown
    FileUtils.rm_rf(@session_path)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
    ENV.delete("OPENAI_API_KEY")
    ENV.delete("GOOGLE_API_KEY")
    ENV.delete("OPENAI_API_BASE")
  end

  def test_initialize_requires_ruby_llm
    # Mock ruby_llm not being available
    ClaudeSwarm::Providers::LlmExecutor.stub :require, ->(_) { raise LoadError } do
      error = assert_raises(ClaudeSwarm::Error) do
        ClaudeSwarm::Providers::LlmExecutor.new(
          provider: "openai",
          model: "gpt-4",
          working_directory: "/tmp"
        )
      end

      assert_match(/ruby_llm gem is not available/, error.message)
      assert_match(/gem install claude-swarm-providers/, error.message)
    end
  end

  def test_initialize_with_missing_api_key
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    ENV.delete("OPENAI_API_KEY")

    with_mocked_ruby_llm do
      error = assert_raises(ClaudeSwarm::Error) do
        ClaudeSwarm::Providers::LlmExecutor.new(
          provider: "openai",
          model: "gpt-4",
          working_directory: "/tmp"
        )
      end

      assert_match(/Missing API key in environment variable: OPENAI_API_KEY/, error.message)
    end
  end

  def test_initialize_with_custom_api_key_env
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    ENV["CUSTOM_KEY"] = "custom-api-key"

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "openai",
        model: "gpt-4",
        api_key_env: "CUSTOM_KEY",
        working_directory: "/tmp"
      )

      assert_instance_of ClaudeSwarm::Providers::LlmExecutor, executor
    end

    ENV.delete("CUSTOM_KEY")
  end

  def test_initialize_with_openai_custom_base_url
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    ENV["CUSTOM_BASE"] = "https://custom.openai.com"

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "openai",
        model: "gpt-4",
        api_base_env: "CUSTOM_BASE",
        working_directory: "/tmp"
      )

      assert_instance_of ClaudeSwarm::Providers::LlmExecutor, executor
    end

    ENV.delete("CUSTOM_BASE")
  end

  def test_execute_logs_request
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "openai",
        model: "gpt-4",
        working_directory: "/tmp",
        instance_name: "test_instance",
        calling_instance: "caller"
      )

      mock_response = MockResponse.new(
        content: "Test response",
        input_tokens: 10,
        output_tokens: 20
      )

      executor.stub :execute_llm_request, mock_response do
        result = executor.execute("Test prompt")

        assert_equal "result", result["type"]
        assert_equal "Test response", result["result"]
        assert_kind_of Integer, result["duration_ms"]
        assert_kind_of Float, result["total_cost"]
        assert_match(/^llm-openai-/, result["session_id"])
      end

      # Check logs
      log_file = File.join(@session_path, "session.log")
      log_content = File.read(log_file)

      assert_match(/caller -> test_instance/, log_content)
      assert_match(/Test prompt/, log_content)
      assert_match(/Test response/, log_content)
    end
  end

  def test_execute_with_system_prompt
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "openai",
        model: "gpt-4",
        working_directory: "/tmp"
      )

      captured_messages = nil
      mock_response = MockResponse.new(content: "Response")

      executor.stub :execute_llm_request, lambda { |messages, _|
        captured_messages = messages
        mock_response
      } do
        executor.execute("User prompt", system_prompt: "System instructions")

        assert_equal 2, captured_messages.length
        assert_equal "system", captured_messages[0][:role]
        assert_equal "System instructions", captured_messages[0][:content]
        assert_equal "user", captured_messages[1][:role]
        assert_equal "User prompt", captured_messages[1][:content]
      end
    end
  end

  def test_execute_with_tools_for_supported_provider
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "openai",
        model: "gpt-4",
        working_directory: "/tmp"
      )

      captured_tools = nil
      mock_response = MockResponse.new(content: "Response")

      executor.stub :execute_llm_request, lambda { |_, tools|
        captured_tools = tools
        mock_response
      } do
        executor.execute("Prompt",
                         allowed_tools: %w[Read Write],
                         disallowed_tools: ["Write"],
                         connections: ["backend"])

        assert_includes captured_tools, "Read"
        refute_includes captured_tools, "Write"
        assert_includes captured_tools, "mcp__backend"
      end
    end
  end

  def test_execute_without_tools_for_unsupported_provider
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "google",
        model: "gemini-pro",
        working_directory: "/tmp"
      )

      captured_tools = nil
      mock_response = MockResponse.new(content: "Response")

      executor.stub :execute_llm_request, lambda { |_, tools|
        captured_tools = tools
        mock_response
      } do
        executor.execute("Prompt", allowed_tools: %w[Read Write])

        assert_nil captured_tools
      end
    end
  end

  def test_error_handling_authentication
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "openai",
        model: "gpt-4",
        working_directory: "/tmp"
      )

      # Mock authentication error
      mock_error = MockRubyLlmError.new("AuthenticationError", "Invalid API key")

      executor.stub :execute_llm_request, ->(*) { raise mock_error } do
        error = assert_raises(ClaudeSwarm::Error) do
          executor.execute("Test")
        end

        assert_match(/Authentication failed/, error.message)
        assert_match(/OPENAI_API_KEY/, error.message)
      end
    end
  end

  def test_error_handling_model_not_found
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "openai",
        model: "gpt-5",
        working_directory: "/tmp"
      )

      # Mock model not found error
      mock_error = MockRubyLlmError.new("ModelNotFoundError", "Model not found")

      executor.stub :execute_llm_request, ->(*) { raise mock_error } do
        error = assert_raises(ClaudeSwarm::Error) do
          executor.execute("Test")
        end

        assert_match(/Model 'gpt-5' not found/, error.message)
        assert_match(/assume_model_exists: true/, error.message)
      end
    end
  end

  def test_error_handling_rate_limit
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "openai",
        model: "gpt-4",
        working_directory: "/tmp"
      )

      # Mock rate limit error
      mock_error = MockRubyLlmError.new("RateLimitError", "Rate limit exceeded")

      executor.stub :execute_llm_request, ->(*) { raise mock_error } do
        error = assert_raises(ClaudeSwarm::Error) do
          executor.execute("Test")
        end

        assert_match(/Rate limit exceeded/, error.message)
      end
    end
  end

  def test_session_persistence
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "openai",
        model: "gpt-4",
        working_directory: "/tmp"
      )

      mock_response = MockResponse.new(content: "Response", input_tokens: 10, output_tokens: 20)

      executor.stub :execute_llm_request, mock_response do
        # First execution creates session
        result1 = executor.execute("First prompt")
        session_id1 = result1["session_id"]

        assert_predicate executor, :has_session?
        assert_match(/^llm-openai-\d{14}-[a-f0-9]{8}$/, session_id1)

        # Second execution uses same session
        result2 = executor.execute("Second prompt")
        session_id2 = result2["session_id"]

        assert_equal session_id1, session_id2
      end
    end
  end

  def test_reset_session
    skip "Test requires mocking ruby_llm" unless can_mock_ruby_llm?

    with_mocked_ruby_llm do
      executor = ClaudeSwarm::Providers::LlmExecutor.new(
        provider: "openai",
        model: "gpt-4",
        working_directory: "/tmp"
      )

      mock_response = MockResponse.new(content: "Response")

      executor.stub :execute_llm_request, mock_response do
        executor.execute("Test")

        assert_predicate executor, :has_session?

        executor.reset_session

        refute_predicate executor, :has_session?
      end
    end
  end

  private

  def can_mock_ruby_llm?
    # Check if we can create mocks for testing
    true
  end

  def with_mocked_ruby_llm(&)
    # Mock the RubyLlm module
    mock_module = Module.new do
      def self.context
        yield(MockLlmConfig.new)
        MockLlmContext.new
      end
    end

    # Temporarily define RubyLlm
    old_ruby_llm = Object.const_defined?(:RubyLlm) ? Object.const_get(:RubyLlm) : nil
    Object.send(:remove_const, :RubyLlm) if old_ruby_llm
    Object.const_set(:RubyLlm, mock_module)

    # Mock require to succeed
    ClaudeSwarm::Providers::LlmExecutor.stub(:require, true, &)
  ensure
    # Restore original RubyLlm if it existed
    Object.send(:remove_const, :RubyLlm) if Object.const_defined?(:RubyLlm)
    Object.const_set(:RubyLlm, old_ruby_llm) if old_ruby_llm
  end

  # Mock classes
  class MockLlmConfig
    attr_accessor :openai_api_key, :openai_api_base, :gemini_api_key, :cohere_api_key
  end

  class MockLlmContext
    def chat(**_options)
      # Return a mock response
      MockResponse.new(
        content: "Mocked response",
        input_tokens: 10,
        output_tokens: 20
      )
    end
  end

  class MockResponse
    attr_reader :content, :input_tokens, :output_tokens

    def initialize(content:, input_tokens: 0, output_tokens: 0)
      @content = content
      @input_tokens = input_tokens
      @output_tokens = output_tokens
    end
  end

  class MockRubyLlmError < StandardError
    def initialize(error_type, message)
      @error_type = error_type
      super(message)

      # Define the error class in RubyLlm if it doesn't exist
      return if ::RubyLlm.const_defined?(error_type.to_sym)

      ::RubyLlm.const_set(error_type.to_sym, Class.new(StandardError))
    end

    def class
      # Return the appropriate RubyLlm error class
      ::RubyLlm.const_get(@error_type.to_sym)
    end
  end
end
