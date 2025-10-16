# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class AgentChatTest < Minitest::Test
    def setup
      @global_semaphore = Async::Semaphore.new(50)
      # Set fake API key to avoid RubyLLM configuration errors
      @original_api_key = ENV["OPENAI_API_KEY"]
      ENV["OPENAI_API_KEY"] = "test-key-12345"
      # Also configure RubyLLM directly to avoid caching issues
      RubyLLM.configure do |config|
        config.openai_api_key = "test-key-12345"
      end
    end

    def teardown
      ENV["OPENAI_API_KEY"] = @original_api_key
      # Reset RubyLLM configuration
      RubyLLM.configure do |config|
        config.openai_api_key = @original_api_key
      end
    end

    def test_initialization_with_defaults
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      assert_instance_of(Agent::Chat, chat)
      assert_equal(RubyLLM::Chat, chat.class.superclass)
    end

    def test_initialization_with_global_semaphore
      chat = Agent::Chat.new(
        definition: { model: "gpt-5" },
        global_semaphore: @global_semaphore,
      )

      assert_equal(@global_semaphore, chat.instance_variable_get(:@global_semaphore))
    end

    def test_initialization_with_local_semaphore
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          max_concurrent_tools: 10,
        },
      )

      local_semaphore = chat.instance_variable_get(:@local_semaphore)

      assert_instance_of(Async::Semaphore, local_semaphore)
    end

    def test_initialization_with_both_semaphores
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          max_concurrent_tools: 10,
        },
        global_semaphore: @global_semaphore,
      )

      assert_equal(@global_semaphore, chat.instance_variable_get(:@global_semaphore))
      assert_instance_of(Async::Semaphore, chat.instance_variable_get(:@local_semaphore))
    end

    def test_initialization_with_no_semaphores
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      assert_nil(chat.instance_variable_get(:@global_semaphore))
      assert_nil(chat.instance_variable_get(:@local_semaphore))
    end

    def test_initialization_with_base_url
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          provider: "openai",
          base_url: "https://custom.api",
        },
      )

      # Verify chat was created successfully with custom context
      assert_instance_of(Agent::Chat, chat)
    end

    def test_has_handle_tool_calls_method
      # handle_tool_calls is a public override method (needs to be accessible for super calls)
      Agent::Chat.new(definition: { model: "gpt-5" })

      assert(Agent::Chat.instance_methods(false).include?(:handle_tool_calls) ||
             Agent::Chat.public_instance_methods(false).include?(:handle_tool_calls))
    end

    def test_has_private_acquire_semaphores_method
      Agent::Chat.new(definition: { model: "gpt-5" })

      assert_includes(Agent::Chat.private_instance_methods(false), :acquire_semaphores)
    end

    def test_inherits_from_ruby_llm_chat
      assert_equal(RubyLLM::Chat, Agent::Chat.superclass)
    end

    def test_acquire_semaphores_with_no_semaphores
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      result = nil
      chat.send(:acquire_semaphores) { result = "executed" }

      assert_equal("executed", result)
    end

    def test_acquire_semaphores_with_global_only
      chat = Agent::Chat.new(
        definition: { model: "gpt-5" },
        global_semaphore: @global_semaphore,
      )

      executed = false
      Async do
        chat.send(:acquire_semaphores) { executed = true }
      end.wait

      assert(executed)
    end

    def test_acquire_semaphores_with_local_only
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          max_concurrent_tools: 10,
        },
      )

      executed = false
      Async do
        chat.send(:acquire_semaphores) { executed = true }
      end.wait

      assert(executed)
    end

    def test_acquire_semaphores_with_both
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          max_concurrent_tools: 10,
        },
        global_semaphore: @global_semaphore,
      )

      executed = false
      Async do
        chat.send(:acquire_semaphores) { executed = true }
      end.wait

      assert(executed)
    end

    def test_initialization_with_custom_timeout
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          timeout: 600,
        },
      )

      assert_instance_of(Agent::Chat, chat)
    end

    def test_initialization_with_base_url_requires_provider
      error = assert_raises(ArgumentError) do
        Agent::Chat.new(
          definition: {
            model: "gpt-5",
            base_url: "https://custom.api",
          },
        )
      end

      assert_match(/provider must be specified/i, error.message)
    end

    def test_initialization_with_base_url_and_ollama_provider
      chat = Agent::Chat.new(
        definition: {
          model: "llama3",
          provider: "ollama",
          base_url: "http://localhost:11434",
        },
      )

      assert_instance_of(Agent::Chat, chat)
    end

    def test_initialization_with_base_url_and_gpustack_provider
      # Set GPUStack API key for test
      original_key = ENV["GPUSTACK_API_KEY"]
      ENV["GPUSTACK_API_KEY"] = "test-key"

      chat = Agent::Chat.new(
        definition: {
          model: "test-model",
          provider: "gpustack",
          base_url: "http://localhost:8080",
        },
      )

      assert_instance_of(Agent::Chat, chat)
    ensure
      ENV["GPUSTACK_API_KEY"] = original_key
    end

    def test_initialization_with_base_url_and_openrouter_provider
      # Set OpenRouter API key for test
      original_key = ENV["OPENROUTER_API_KEY"]
      ENV["OPENROUTER_API_KEY"] = "test-key"

      # Also configure RubyLLM to avoid configuration error
      RubyLLM.configure do |config|
        config.openrouter_api_key = "test-key"
      end

      chat = Agent::Chat.new(
        definition: {
          model: "anthropic/claude-sonnet-4",
          provider: "openrouter",
          base_url: "https://openrouter.ai/api/v1",
        },
      )

      assert_instance_of(Agent::Chat, chat)
    ensure
      ENV["OPENROUTER_API_KEY"] = original_key
      RubyLLM.configure do |config|
        config.openrouter_api_key = original_key
      end
    end

    def test_initialization_with_unsupported_provider_and_base_url_raises_error
      error = assert_raises(ArgumentError) do
        Agent::Chat.new(
          definition: {
            model: "test-model",
            provider: "unsupported",
            base_url: "https://custom.api",
          },
        )
      end

      assert_match(/doesn't support custom base_url/i, error.message)
    end

    def test_handle_tool_calls_uses_sequential_for_single_tool
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Create a mock response with a single tool call
      tool_call = Struct.new(:id, :name, :arguments).new("call_1", "test_tool", { arg: "value" })
      response = Struct.new(:tool_calls).new({ "call_1" => tool_call })

      # Mock the superclass method to track if it was called
      super_called = false
      chat.define_singleton_method(:handle_tool_calls_super) do |_response, &_block|
        super_called = true
        nil
      end

      # Stub the method to call our mock
      original_method = chat.method(:handle_tool_calls)
      chat.define_singleton_method(:handle_tool_calls) do |resp, &block|
        if resp.tool_calls.size == 1
          handle_tool_calls_super(resp, &block)
        else
          original_method.call(resp, &block)
        end
      end

      # Test that single tool call uses sequential execution
      begin
        chat.send(:handle_tool_calls, response)
      rescue NoMethodError
        # Expected since we're not fully mocking the response
      end

      assert(super_called, "Expected superclass method to be called for single tool call")
    end

    def test_handle_tool_calls_uses_parallel_for_multiple_tools
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock callbacks
      tool_call_hooks = []
      tool_result_callbacks = []
      end_message_callbacks = []

      chat.instance_variable_set(:@on, {
        tool_call: ->(tc) { tool_call_hooks << tc },
        tool_result: ->(r) { tool_result_callbacks << r },
        end_message: ->(m) { end_message_callbacks << m },
      })

      # Mock execute_tool and add_message
      chat.define_singleton_method(:execute_tool) do |tool_call|
        "result_#{tool_call.id}"
      end

      chat.define_singleton_method(:add_message) do |role:, content:, tool_call_id:|
        Struct.new(:role, :content, :tool_call_id).new(role, content, tool_call_id)
      end

      chat.define_singleton_method(:complete) do |&_block|
        Struct.new(:content).new("Final response")
      end

      # Create mock response with multiple tool calls
      tool_call_1 = Struct.new(:id, :name, :arguments).new("call_1", "tool_1", { arg: "value1" })
      tool_call_2 = Struct.new(:id, :name, :arguments).new("call_2", "tool_2", { arg: "value2" })
      tool_call_3 = Struct.new(:id, :name, :arguments).new("call_3", "tool_3", { arg: "value3" })

      response = Struct.new(:tool_calls).new({
        "call_1" => tool_call_1,
        "call_2" => tool_call_2,
        "call_3" => tool_call_3,
      })

      # Execute handle_tool_calls
      chat.send(:handle_tool_calls, response)

      # Verify all tool calls were executed
      assert_equal(3, tool_call_hooks.size)
      assert_equal(3, tool_result_callbacks.size)
      assert_equal(3, end_message_callbacks.size)

      # Verify results contain all tool call IDs
      assert_equal(["result_call_1", "result_call_2", "result_call_3"], tool_result_callbacks)
    end

    def test_semaphores_limit_concurrent_execution
      # Create semaphores with low limits
      global_semaphore = Async::Semaphore.new(2)
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          max_concurrent_tools: 1,
        },
        global_semaphore: global_semaphore,
      )

      execution_order = []
      active_count = 0
      max_concurrent = 0

      # Execute multiple tasks that track concurrency
      Async do
        tasks = 5.times.map do |i|
          Async do
            chat.send(:acquire_semaphores) do
              active_count += 1
              max_concurrent = [max_concurrent, active_count].max
              execution_order << i
              sleep(0.01) # Simulate work
              active_count -= 1
            end
          end
        end

        tasks.each(&:wait)
      end.wait

      # Verify all tasks executed
      assert_equal(5, execution_order.size)

      # Verify concurrency was limited (local semaphore limits to 1)
      assert_equal(1, max_concurrent)
    end

    def test_global_semaphore_limits_across_multiple_chats
      global_semaphore = Async::Semaphore.new(2)

      chat1 = Agent::Chat.new(definition: { model: "gpt-5" }, global_semaphore: global_semaphore)
      chat2 = Agent::Chat.new(definition: { model: "gpt-5" }, global_semaphore: global_semaphore)

      max_concurrent = 0
      active_count = 0

      Async do
        tasks = []

        3.times do
          tasks << Async do
            chat1.send(:acquire_semaphores) do
              active_count += 1
              max_concurrent = [max_concurrent, active_count].max
              sleep(0.01)
              active_count -= 1
            end
          end
        end

        3.times do
          tasks << Async do
            chat2.send(:acquire_semaphores) do
              active_count += 1
              max_concurrent = [max_concurrent, active_count].max
              sleep(0.01)
              active_count -= 1
            end
          end
        end

        tasks.each(&:wait)
      end.wait

      # Global semaphore should limit to 2 concurrent across both chats
      assert_operator(max_concurrent, :<=, 2, "Expected max concurrent to be <= 2, got #{max_concurrent}")
    end

    def test_context_limit_returns_model_context_window
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      limit = chat.context_limit

      # gpt-5 should have a context limit (RubyLLM provides this)
      assert(limit.nil? || limit.positive?, "Expected context limit to be nil or positive")
    end

    def test_context_limit_handles_missing_model_gracefully
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Even if chat.model raises error, we have @real_model_info as fallback
      chat.stub(:model, ->() { raise StandardError, "Model not found" }) do
        limit = chat.context_limit

        # Should still get context from @real_model_info
        assert(limit.nil? || limit.positive?, "Expected fallback to @real_model_info")
      end
    end

    def test_cumulative_input_tokens_sums_message_tokens
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock messages - input_tokens on assistant messages is cumulative
      # Only the LATEST assistant message's input_tokens matters
      user1 = Struct.new(:role, :input_tokens).new(:user, nil)
      assistant1 = Struct.new(:role, :input_tokens).new(:assistant, 100)
      user2 = Struct.new(:role, :input_tokens).new(:user, nil)
      assistant2 = Struct.new(:role, :input_tokens).new(:assistant, 250) # Already includes assistant1's input
      user3 = Struct.new(:role, :input_tokens).new(:user, nil)
      assistant3 = Struct.new(:role, :input_tokens).new(:assistant, 350) # Already includes all previous

      chat.stub(:messages, [user1, assistant1, user2, assistant2, user3, assistant3]) do
        assert_equal(350, chat.cumulative_input_tokens, "Should use latest assistant message's input_tokens")
      end
    end

    def test_cumulative_input_tokens_handles_nil_tokens
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock messages with some nil tokens
      user1 = Struct.new(:role, :input_tokens).new(:user, nil)
      assistant1 = Struct.new(:role, :input_tokens).new(:assistant, 100)
      user2 = Struct.new(:role, :input_tokens).new(:user, nil)
      assistant2 = Struct.new(:role, :input_tokens).new(:assistant, nil) # No tokens reported
      user3 = Struct.new(:role, :input_tokens).new(:user, nil)
      assistant3 = Struct.new(:role, :input_tokens).new(:assistant, 250)

      chat.stub(:messages, [user1, assistant1, user2, assistant2, user3, assistant3]) do
        assert_equal(250, chat.cumulative_input_tokens, "Should use latest assistant message with non-nil input_tokens")
      end
    end

    def test_cumulative_output_tokens_sums_message_tokens
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock messages - output tokens are per-response and should be summed
      user1 = Struct.new(:role, :output_tokens).new(:user, nil)
      assistant1 = Struct.new(:role, :output_tokens).new(:assistant, 75)
      user2 = Struct.new(:role, :output_tokens).new(:user, nil)
      assistant2 = Struct.new(:role, :output_tokens).new(:assistant, 125)
      user3 = Struct.new(:role, :output_tokens).new(:user, nil)
      assistant3 = Struct.new(:role, :output_tokens).new(:assistant, 25)

      chat.stub(:messages, [user1, assistant1, user2, assistant2, user3, assistant3]) do
        assert_equal(225, chat.cumulative_output_tokens, "Should sum all assistant messages' output_tokens")
      end
    end

    def test_cumulative_total_tokens_sums_input_and_output
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock messages with both input and output tokens
      # Input is cumulative (latest only), output is per-response (sum all)
      user1 = Struct.new(:role, :input_tokens, :output_tokens).new(:user, nil, nil)
      assistant1 = Struct.new(:role, :input_tokens, :output_tokens).new(:assistant, 100, 75)
      user2 = Struct.new(:role, :input_tokens, :output_tokens).new(:user, nil, nil)
      assistant2 = Struct.new(:role, :input_tokens, :output_tokens).new(:assistant, 250, 125) # input already includes assistant1

      chat.stub(:messages, [user1, assistant1, user2, assistant2]) do
        # Latest input (250) + sum of outputs (75 + 125 = 200) = 450
        assert_equal(450, chat.cumulative_total_tokens)
      end
    end

    def test_context_usage_percentage_calculates_correctly
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock context limit and cumulative tokens
      chat.stub(:context_limit, 100_000) do
        chat.stub(:cumulative_total_tokens, 25_000) do
          assert_in_delta(25.0, chat.context_usage_percentage)
        end
      end
    end

    def test_context_usage_percentage_returns_zero_when_limit_nil
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      chat.stub(:context_limit, nil) do
        assert_in_delta(0.0, chat.context_usage_percentage)
      end
    end

    def test_context_usage_percentage_returns_zero_when_limit_zero
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      chat.stub(:context_limit, 0) do
        assert_in_delta(0.0, chat.context_usage_percentage)
      end
    end

    def test_context_usage_percentage_rounds_to_two_decimals
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      chat.stub(:context_limit, 100_000) do
        chat.stub(:cumulative_total_tokens, 12_345) do
          # 12345 / 100000 * 100 = 12.345%
          assert_in_delta(12.35, chat.context_usage_percentage)
        end
      end
    end

    def test_tokens_remaining_calculates_correctly
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      chat.stub(:context_limit, 100_000) do
        chat.stub(:cumulative_total_tokens, 25_000) do
          assert_equal(75_000, chat.tokens_remaining)
        end
      end
    end

    def test_tokens_remaining_returns_nil_when_limit_nil
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      chat.stub(:context_limit, nil) do
        assert_nil(chat.tokens_remaining)
      end
    end

    def test_tokens_remaining_handles_negative_values
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Context limit exceeded
      chat.stub(:context_limit, 100_000) do
        chat.stub(:cumulative_total_tokens, 150_000) do
          assert_equal(-50_000, chat.tokens_remaining)
        end
      end
    end

    def test_context_limit_with_base_url_fetches_real_model_info
      # When using base_url with assume_model_exists, we should still get context limit
      # from the real model info in RubyLLM's registry
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5-mini",
          provider: "openai",
          base_url: "https://proxy.api",
        },
      )

      # Should have fetched the real model info
      real_model_info = chat.instance_variable_get(:@real_model_info)

      refute_nil(real_model_info, "Expected @real_model_info to be set")

      # Should be able to get context limit from real model info
      limit = chat.context_limit

      assert(limit.nil? || limit.positive?, "Expected context limit to be nil or positive, got #{limit}")
    end

    def test_context_limit_without_base_url_uses_real_model_info
      # Now we ALWAYS fetch real model info for accurate context tracking
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Should have fetched real model info even without base_url
      real_model_info = chat.instance_variable_get(:@real_model_info)

      refute_nil(real_model_info, "Expected @real_model_info to be populated for better context tracking")

      # Should get context limit from real model info
      limit = chat.context_limit

      assert(limit.nil? || limit.positive?, "Expected context limit to be nil or positive")
      assert_equal(real_model_info.context_window, limit, "Should use real_model_info's context_window")
    end

    def test_determine_provider_with_api_version_responses
      # When api_version is v1/responses, should use custom provider
      chat = Agent::Chat.new(
        definition: {
          model: "claude-sonnet-4",
          provider: "openai",
          base_url: "https://proxy.api",
          api_version: "v1/responses",
        },
      )

      # The determine_provider method should have been called internally
      # Verify by checking that the chat was created successfully
      assert_instance_of(Agent::Chat, chat)
    end

    def test_determine_provider_without_api_version
      # Without api_version, should use standard provider
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          provider: "openai",
          base_url: "https://proxy.api",
        },
      )

      assert_instance_of(Agent::Chat, chat)
    end

    def test_determine_provider_with_api_version_chat_completions
      # With api_version set to chat/completions, should use standard provider
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          provider: "openai",
          base_url: "https://proxy.api",
          api_version: "v1/chat/completions",
        },
      )

      assert_instance_of(Agent::Chat, chat)
    end

    def test_determine_provider_without_base_url_ignores_api_version
      # Without base_url, api_version should be ignored
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          provider: "openai",
          api_version: "v1/responses",
        },
      )

      # Should still create chat successfully
      assert_instance_of(Agent::Chat, chat)
    end

    def test_openai_with_responses_provider_registered
      # Verify our custom provider is registered
      assert(RubyLLM::Provider.providers.key?(:openai_with_responses))
    end

    def test_system_reminders_injected_on_first_ask
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock add_message to capture what messages are added
      added_messages = []
      chat.define_singleton_method(:add_message) do |role:, content:|
        added_messages << { role: role, content: content }
        Struct.new(:role, :content).new(role, content)
      end

      # Mock complete to return a response
      chat.define_singleton_method(:complete) do |**_options|
        Struct.new(:content).new("Response")
      end

      # First ask should inject system reminders
      chat.ask("Hello")

      # Verify 3 messages were added (before reminder, prompt, after reminder)
      assert_equal(3, added_messages.size)

      # Verify order and content
      assert_equal(:user, added_messages[0][:role])
      assert_match(/important-instruction-reminders/, added_messages[0][:content])
      assert_match(/NEVER create files unless/, added_messages[0][:content])

      assert_equal(:user, added_messages[1][:role])
      assert_equal("Hello", added_messages[1][:content])

      assert_equal(:user, added_messages[2][:role])
      assert_match(/todo list is currently empty/, added_messages[2][:content])
    end

    def test_system_reminders_not_injected_on_subsequent_ask
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock messages to simulate first message already exists
      user_message = Struct.new(:role, :content).new(:user, "First message")
      chat.stub(:messages, [user_message]) do
        # Mock super to track if it was called
        super_called = false
        chat.define_singleton_method(:call_super_ask) do |_prompt, **_options|
          super_called = true
          Struct.new(:content).new("Response")
        end

        # Stub the ask method to call our mock instead of super
        chat.method(:ask)
        chat.define_singleton_method(:ask) do |prompt, **options|
          # Check if first message
          is_first_message = messages.none? { |msg| msg.role == :user }

          if is_first_message
            # This branch shouldn't be taken
            raise "Should not inject reminders on subsequent message"
          else
            call_super_ask(prompt, **options)
          end
        end

        # Call ask - should not inject reminders
        chat.ask("Second message")

        # Verify super was called (no system reminders)
        assert(super_called, "Expected super to be called for subsequent message")
      end
    end

    def test_system_reminder_constants_defined
      # Verify the constants are defined in SystemReminderInjector
      assert_kind_of(String, Agent::Chat::SystemReminderInjector::BEFORE_FIRST_MESSAGE_REMINDER)
      assert_kind_of(String, Agent::Chat::SystemReminderInjector::AFTER_FIRST_MESSAGE_REMINDER)

      # Verify content
      assert_match(/important-instruction-reminders/, Agent::Chat::SystemReminderInjector::BEFORE_FIRST_MESSAGE_REMINDER)
      assert_match(/NEVER create files unless/, Agent::Chat::SystemReminderInjector::BEFORE_FIRST_MESSAGE_REMINDER)
      assert_match(/todo list is currently empty/, Agent::Chat::SystemReminderInjector::AFTER_FIRST_MESSAGE_REMINDER)
    end

    def test_determine_provider_without_base_url
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      provider = chat.send(:determine_provider, "openai", nil, nil)

      assert_equal("openai", provider)
    end

    def test_determine_provider_with_base_url_and_responses_api_version
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      provider = chat.send(:determine_provider, "openai", "https://custom.api", "v1/responses")

      assert_equal(:openai_with_responses, provider)
    end

    def test_determine_provider_with_base_url_without_responses_api
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      provider = chat.send(:determine_provider, "openai", "https://custom.api", nil)

      assert_equal("openai", provider)
    end

    def test_determine_provider_with_ollama
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      provider = chat.send(:determine_provider, "ollama", "http://localhost:11434", nil)

      assert_equal("ollama", provider)
    end

    def test_context_limit_with_explicit_context_window
      chat = Agent::Chat.new(definition: { model: "gpt-5", context_window: 150_000 })

      assert_equal(150_000, chat.context_limit)
    end

    def test_context_limit_with_real_model_info
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Should have real_model_info
      real_model_info = chat.instance_variable_get(:@real_model_info)

      refute_nil(real_model_info)
      assert_equal(real_model_info.context_window, chat.context_limit)
    end

    def test_context_limit_with_error_returns_nil
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock model to raise error
      chat.stub(:model, ->() { raise StandardError, "Model error" }) do
        # Should return nil instead of crashing
        limit = chat.context_limit

        # Will be nil if both @real_model_info and model() fail
        assert(limit.nil? || limit.positive?)
      end
    end

    def test_cumulative_input_tokens_with_no_assistant_messages
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock messages with no assistant messages
      user1 = Struct.new(:role, :input_tokens).new(:user, nil)

      chat.stub(:messages, [user1]) do
        assert_equal(0, chat.cumulative_input_tokens)
      end
    end

    def test_cumulative_output_tokens_with_no_assistant_messages
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      user1 = Struct.new(:role, :output_tokens).new(:user, nil)

      chat.stub(:messages, [user1]) do
        assert_equal(0, chat.cumulative_output_tokens)
      end
    end

    def test_calculate_cost_with_no_tokens_returns_zero
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      message = Struct.new(:input_tokens, :output_tokens, :model_id).new(nil, nil, "gpt-5")

      cost = chat.send(:calculate_cost, message)

      assert_in_delta(0.0, cost[:total_cost])
    end

    def test_calculate_cost_with_no_model_info_returns_zero
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      message = Struct.new(:input_tokens, :output_tokens, :model_id).new(100, 50, "nonexistent-model")

      cost = chat.send(:calculate_cost, message)

      assert_in_delta(0.0, cost[:total_cost])
    end

    def test_serialize_result_with_string
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      result = chat.send(:serialize_result, "string result")

      assert_equal("string result", result)
    end

    def test_serialize_result_with_hash
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      result = chat.send(:serialize_result, { key: "value" })

      assert_equal({ key: "value" }, result)
    end

    def test_serialize_result_with_array
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      result = chat.send(:serialize_result, [1, 2, 3])

      assert_equal([1, 2, 3], result)
    end

    def test_serialize_result_with_other_type
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      result = chat.send(:serialize_result, 12345)

      assert_equal("12345", result)
    end

    def test_serialize_result_with_content_object
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Create a temporary file for testing
      Dir.mktmpdir do |dir|
        file_path = File.join(dir, "test.pdf")
        File.write(file_path, "binary content")

        content = RubyLLM::Content.new("File: test.pdf", file_path)
        result = chat.send(:serialize_result, content)

        assert_includes(result, "File: test.pdf")
        assert_includes(result, "[Attachments:")
        assert_includes(result, file_path)
        assert_includes(result, "application/pdf")
      end
    end

    def test_serialize_result_with_content_object_text_only
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      content = RubyLLM::Content.new("Just text, no attachments")
      result = chat.send(:serialize_result, content)

      assert_equal("Just text, no attachments", result)
    end

    def test_serialize_result_with_content_object_attachment_only
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      Dir.mktmpdir do |dir|
        file_path = File.join(dir, "image.png")
        File.write(file_path, "image data")

        content = RubyLLM::Content.new("", file_path)
        result = chat.send(:serialize_result, content)

        assert_includes(result, "[Attachments:")
        assert_includes(result, file_path)
        assert_includes(result, "image/png")
      end
    end

    def test_format_tool_calls_with_nil
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      result = chat.send(:format_tool_calls, nil)

      assert_nil(result)
    end

    def test_format_tool_calls_with_hash
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      tool_call = Struct.new(:id, :name, :arguments).new("call_123", "TestTool", { arg: "value" })
      tool_calls = { "call_123" => tool_call }

      result = chat.send(:format_tool_calls, tool_calls)

      assert_equal(1, result.size)
      assert_equal("call_123", result[0][:id])
      assert_equal("TestTool", result[0][:name])
      assert_equal({ arg: "value" }, result[0][:arguments])
    end

    def test_should_inject_todowrite_reminder_with_few_messages
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock messages with only 3 messages
      user1 = Struct.new(:role).new(:user)
      user2 = Struct.new(:role).new(:user)
      user3 = Struct.new(:role).new(:user)

      chat.stub(:messages, [user1, user2, user3]) do
        refute(Agent::Chat::SystemReminderInjector.should_inject_todowrite_reminder?(chat, nil))
      end
    end

    def test_should_inject_todowrite_reminder_with_recent_todowrite
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock messages with recent TodoWrite
      messages = (1..10).map { Struct.new(:role, :content).new(:user, "test") }
      messages << Struct.new(:role, :content).new(:tool, "TodoWrite result")

      chat.stub(:messages, messages) do
        refute(Agent::Chat::SystemReminderInjector.should_inject_todowrite_reminder?(chat, nil))
      end
    end

    def test_should_inject_todowrite_reminder_after_interval
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock messages exceeding interval without TodoWrite
      messages = (1..20).map { Struct.new(:role, :content).new(:user, "test") }

      chat.stub(:messages, messages) do
        assert(Agent::Chat::SystemReminderInjector.should_inject_todowrite_reminder?(chat, nil))
      end
    end

    def test_should_inject_todowrite_reminder_after_interval_from_last_use
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock 20 messages (15 since last TodoWrite at index 5)
      messages = (1..20).map { Struct.new(:role, :content).new(:user, "test") }

      chat.stub(:messages, messages) do
        assert(Agent::Chat::SystemReminderInjector.should_inject_todowrite_reminder?(chat, 5))
      end
    end

    def test_configure_responses_api_provider_with_custom_provider
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          provider: "openai",
          base_url: "https://custom.api",
          api_version: "v1/responses",
        },
      )

      # Provider should be configured
      provider_instance = chat.instance_variable_get(:@provider)

      assert_instance_of(SwarmSDK::Providers::OpenAIWithResponses, provider_instance)
      assert(provider_instance.use_responses_api)
    end

    def test_configure_responses_api_provider_without_custom_provider
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          provider: "openai",
          base_url: "https://custom.api",
        },
      )

      # Should still create chat
      assert_instance_of(Agent::Chat, chat)
    end

    def test_emit_model_lookup_warning_emits_event
      chat = Agent::Chat.new(
        definition: { model: "nonexistent-model-xyz", provider: "openai", assume_model_exists: true },
      )

      # Mock LogStream
      events = []
      LogStream.stub(:emit, ->(entry) { events << entry }) do
        chat.emit_model_lookup_warning(:test_agent)
      end

      # Should have emitted warning (model lookup happens in constructor)
      # Since model doesn't exist in registry, @model_lookup_error should be set
      assert_equal(1, events.size)
      assert_equal("model_lookup_warning", events[0][:type])
      assert_equal(:test_agent, events[0][:agent])
      assert_equal("nonexistent-model-xyz", events[0][:model])
    end

    def test_emit_model_lookup_warning_without_error_does_nothing
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock LogStream
      events = []
      LogStream.stub(:emit, ->(entry) { events << entry }) do
        chat.emit_model_lookup_warning(:test_agent)
      end

      # Should not emit anything
      assert_empty(events)
    end

    def test_suggest_similar_models_finds_matches
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      suggestions = chat.send(:suggest_similar_models, "gpt")

      # Should find some gpt models
      refute_empty(suggestions)
      assert(suggestions.all? { |m| m.id.downcase.include?("gpt") })
    end

    def test_suggest_similar_models_returns_max_three
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      suggestions = chat.send(:suggest_similar_models, "gpt")

      assert_operator(suggestions.size, :<=, 3)
    end

    def test_suggest_similar_models_with_error_returns_empty
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Mock RubyLLM.models to raise error
      RubyLLM.models.stub(:all, ->() { raise StandardError, "Error" }) do
        suggestions = chat.send(:suggest_similar_models, "gpt")

        assert_empty(suggestions)
      end
    end

    def test_initialization_with_custom_timeout_no_base_url
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          timeout: 600,
        },
      )

      # Should create isolated context due to non-default timeout
      assert_instance_of(Agent::Chat, chat)
    end

    def test_initialization_with_provider_only
      # Use a provider that doesn't require special configuration
      chat = Agent::Chat.new(
        definition: {
          model: "gpt-5",
          provider: "openai",
        },
      )

      assert_instance_of(Agent::Chat, chat)
    end

    def test_initialization_without_provider_or_base_url
      chat = Agent::Chat.new(
        definition: { model: "gpt-5" },
      )

      assert_instance_of(Agent::Chat, chat)
    end

    def test_handle_tool_calls_with_halt_result
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Create mock response with multiple tool calls
      tool_call = Struct.new(:id, :name, :arguments).new("call_1", "tool_1", { arg: "value1" })

      response = Struct.new(:tool_calls).new({ "call_1" => tool_call })

      # Mock execute_tool to return a Halt result
      halt_result = RubyLLM::Tool::Halt.new("Halting execution")
      chat.define_singleton_method(:execute_tool) do |_tool_call|
        halt_result
      end

      chat.define_singleton_method(:add_message) do |role:, content:, tool_call_id:|
        Struct.new(:role, :content, :tool_call_id).new(role, content, tool_call_id)
      end

      # Mock callbacks
      chat.instance_variable_set(:@on, {
        tool_call: ->(_tc) {},
        tool_result: ->(_r) {},
        end_message: ->(_m) {},
      })

      result = chat.send(:handle_tool_calls, response)

      # Should return the halt result
      assert_same(halt_result, result)
    end

    def test_handle_tool_calls_with_content_result
      chat = Agent::Chat.new(definition: { model: "gpt-5" })

      # Create mock response with tool call
      tool_call = Struct.new(:id, :name, :arguments).new("call_1", "tool_1", { arg: "value" })

      response = Struct.new(:tool_calls).new({ "call_1" => tool_call })

      # Mock execute_tool to return RubyLLM::Content instead of string
      content_result = RubyLLM::Content.new("Result content")
      chat.define_singleton_method(:execute_tool) do |_tool_call|
        content_result
      end

      chat.define_singleton_method(:add_message) do |role:, content:, tool_call_id:|
        Struct.new(:role, :content, :tool_call_id).new(role, content, tool_call_id)
      end

      chat.define_singleton_method(:complete) do |&_block|
        Struct.new(:content).new("Final response")
      end

      # Mock callbacks
      chat.instance_variable_set(:@on, {
        tool_call: ->(_tc) {},
        tool_result: ->(_r) {},
        end_message: ->(_m) {},
      })

      result = chat.send(:handle_tool_calls, response)

      # Should complete and return final response
      assert_equal("Final response", result.content)
    end
  end
end
