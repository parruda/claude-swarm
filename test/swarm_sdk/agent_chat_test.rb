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
      chat = AgentChat.new(model: "gpt-5")

      assert_instance_of(AgentChat, chat)
      assert_equal(RubyLLM::Chat, chat.class.superclass)
    end

    def test_initialization_with_global_semaphore
      chat = AgentChat.new(
        model: "gpt-5",
        global_semaphore: @global_semaphore,
      )

      assert_equal(@global_semaphore, chat.instance_variable_get(:@global_semaphore))
    end

    def test_initialization_with_local_semaphore
      chat = AgentChat.new(
        model: "gpt-5",
        max_concurrent_tools: 10,
      )

      local_semaphore = chat.instance_variable_get(:@local_semaphore)

      assert_instance_of(Async::Semaphore, local_semaphore)
    end

    def test_initialization_with_both_semaphores
      chat = AgentChat.new(
        model: "gpt-5",
        global_semaphore: @global_semaphore,
        max_concurrent_tools: 10,
      )

      assert_equal(@global_semaphore, chat.instance_variable_get(:@global_semaphore))
      assert_instance_of(Async::Semaphore, chat.instance_variable_get(:@local_semaphore))
    end

    def test_initialization_with_no_semaphores
      chat = AgentChat.new(model: "gpt-5")

      assert_nil(chat.instance_variable_get(:@global_semaphore))
      assert_nil(chat.instance_variable_get(:@local_semaphore))
    end

    def test_initialization_with_base_url
      chat = AgentChat.new(
        model: "gpt-5",
        provider: "openai",
        base_url: "https://custom.api",
      )

      # Verify chat was created successfully with custom context
      assert_instance_of(AgentChat, chat)
    end

    def test_has_private_handle_tool_calls_method
      AgentChat.new(model: "gpt-5")

      assert_includes(AgentChat.private_instance_methods(false), :handle_tool_calls)
    end

    def test_has_private_acquire_semaphores_method
      AgentChat.new(model: "gpt-5")

      assert_includes(AgentChat.private_instance_methods(false), :acquire_semaphores)
    end

    def test_inherits_from_ruby_llm_chat
      assert_equal(RubyLLM::Chat, AgentChat.superclass)
    end

    def test_acquire_semaphores_with_no_semaphores
      chat = AgentChat.new(model: "gpt-5")

      result = nil
      chat.send(:acquire_semaphores) { result = "executed" }

      assert_equal("executed", result)
    end

    def test_acquire_semaphores_with_global_only
      chat = AgentChat.new(
        model: "gpt-5",
        global_semaphore: @global_semaphore,
      )

      executed = false
      Async do
        chat.send(:acquire_semaphores) { executed = true }
      end.wait

      assert(executed)
    end

    def test_acquire_semaphores_with_local_only
      chat = AgentChat.new(
        model: "gpt-5",
        max_concurrent_tools: 10,
      )

      executed = false
      Async do
        chat.send(:acquire_semaphores) { executed = true }
      end.wait

      assert(executed)
    end

    def test_acquire_semaphores_with_both
      chat = AgentChat.new(
        model: "gpt-5",
        global_semaphore: @global_semaphore,
        max_concurrent_tools: 10,
      )

      executed = false
      Async do
        chat.send(:acquire_semaphores) { executed = true }
      end.wait

      assert(executed)
    end
  end
end
