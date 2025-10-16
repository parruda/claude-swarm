# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ContextCompactorTest < Minitest::Test
    def setup
      @chat = create_mock_chat
      @compactor = ContextCompactor.new(@chat)
    end

    def test_prune_tool_results_truncates_long_results
      # Create messages with long tool result
      long_result = "x" * 1000
      messages = [
        create_message(:user, "test"),
        create_message(:tool, long_result, tool_call_id: "1"),
      ]

      pruned = @compactor.send(:prune_tool_results, messages)

      # Tool result should be truncated
      assert_equal(2, pruned.size)
      assert_operator(pruned[1].content.length, :<, long_result.length)
      assert_includes(pruned[1].content, "truncated by context compaction")
    end

    def test_prune_tool_results_preserves_short_results
      # Create messages with short tool result
      short_result = "OK"
      messages = [
        create_message(:user, "test"),
        create_message(:tool, short_result, tool_call_id: "1"),
      ]

      pruned = @compactor.send(:prune_tool_results, messages)

      # Tool result should NOT be truncated
      assert_equal(2, pruned.size)
      assert_equal(short_result, pruned[1].content)
    end

    def test_create_checkpoint_if_needed_does_not_checkpoint_short_conversations
      # Create conversation with fewer messages than threshold
      messages = 20.times.map { |i| create_message(:user, "message #{i}") }

      checkpointed = @compactor.send(:create_checkpoint_if_needed, messages)

      # Should return original messages (no checkpoint)
      assert_equal(messages.size, checkpointed.size)
      refute(checkpointed.any? { |m| m.content.to_s.include?("CHECKPOINT") })
    end

    def test_create_checkpoint_if_needed_creates_checkpoint_for_long_conversations
      # Mock the summarization to avoid real LLM calls
      stub_summarization(@compactor)

      # Create conversation with more messages than threshold
      messages = 60.times.map { |i| create_message(:user, "message #{i}") }

      checkpointed = @compactor.send(:create_checkpoint_if_needed, messages)

      # Should have fewer messages + a checkpoint message
      assert_operator(checkpointed.size, :<, messages.size)
      assert(checkpointed.any? { |m| m.content.to_s.include?("CHECKPOINT") })
    end

    def test_apply_sliding_window_keeps_recent_messages
      # Create many messages
      messages = 50.times.map { |i| create_message(:user, "message #{i}") }

      windowed = @compactor.send(:apply_sliding_window, messages)

      # Should keep only sliding window size
      assert_equal(20, windowed.size)
      # Should keep the most recent messages
      assert_includes(windowed.last.content, "message 49")
    end

    def test_apply_sliding_window_preserves_system_messages
      # Create system message + many user messages
      messages = [create_message(:system, "You are an assistant")]
      messages += 50.times.map { |i| create_message(:user, "message #{i}") }

      windowed = @compactor.send(:apply_sliding_window, messages)

      # Should keep system message + sliding window
      assert(windowed.any? { |m| m.role == :system })
      assert_includes(windowed.first.content, "You are an assistant")
    end

    def test_compact_emits_events
      # Mock LogStream to capture events
      events = []
      original_emitter = LogStream.emitter
      LogStream.emitter = MockEmitter.new(events)

      # Mock summarization
      stub_summarization(@compactor)

      # Add some messages to chat
      10.times { |i| @chat.messages << create_message(:user, "message #{i}") }

      # Compact
      @compactor.compact

      # Should emit compression_started and compression_completed events
      assert(events.any? { |e| e[:type] == "compression_started" })
      assert(events.any? { |e| e[:type] == "compression_completed" })
    ensure
      LogStream.emitter = original_emitter
    end

    def test_compact_returns_metrics
      # Mock summarization
      stub_summarization(@compactor)

      # Add messages to chat
      20.times { |i| @chat.messages << create_message(:user, "message #{i}") }
      original_count = @chat.messages.size

      # Compact
      metrics = @compactor.compact

      # Should return Metrics object
      assert_instance_of(ContextCompactor::Metrics, metrics)
      assert_equal(original_count, metrics.original_message_count)
      assert_operator(metrics.compressed_message_count, :<=, original_count)
      assert_operator(metrics.time_taken, :>=, 0)
    end

    def test_compact_reduces_message_count
      # Mock summarization
      stub_summarization(@compactor)

      # Add many messages to trigger compression
      100.times { |i| @chat.messages << create_message(:user, "message #{i}") }
      original_count = @chat.messages.size

      # Compact
      @compactor.compact

      # Should reduce message count
      assert_operator(@chat.messages.size, :<, original_count)
    end

    def test_compact_with_custom_options
      # Create compactor with custom options
      custom_compactor = ContextCompactor.new(@chat, {
        tool_result_max_length: 100,
        checkpoint_threshold: 30,
        sliding_window_size: 10,
      })

      # Mock summarization
      stub_summarization(custom_compactor)

      # Add messages
      50.times { |i| @chat.messages << create_message(:user, "message #{i}") }

      # Compact
      custom_compactor.compact

      # Should use custom sliding window size
      # (accounting for potential system messages)
      assert_operator(@chat.messages.size, :<=, 11) # 10 + possible system messages
    end

    private

    # Create a mock chat instance
    def create_mock_chat
      # Create a minimal mock that has the necessary interface
      chat = Minitest::Mock.new
      chat.expect(:messages, [])
      chat.expect(:provider, Minitest::Mock.new)

      # Setup provider mock
      provider = chat.provider
      provider.expect(:agent_name, :test_agent) if provider.respond_to?(:expect)
      provider.expect(:respond_to?, true, [:agent_name]) if provider.respond_to?(:expect)
      provider.expect(:client, create_mock_client) if provider.respond_to?(:expect)

      # Use a simple object that responds to messages
      mock_chat = Object.new
      mock_chat.define_singleton_method(:messages) { @messages ||= [] }
      mock_chat.define_singleton_method(:provider) do
        provider_obj = Object.new
        provider_obj.define_singleton_method(:agent_name) { :test_agent }
        provider_obj.define_singleton_method(:respond_to?) { |method| method == :agent_name }
        provider_obj.define_singleton_method(:client) { create_mock_client }
        provider_obj
      end

      mock_chat
    end

    # Create a mock RubyLLM client
    def create_mock_client
      client = Object.new
      client.define_singleton_method(:context) { RubyLLM.context }
      client
    end

    # Create a mock message
    def create_message(role, content, tool_call_id: nil)
      msg = Object.new
      msg.define_singleton_method(:role) { role }
      msg.define_singleton_method(:content) { content }
      msg.define_singleton_method(:tool_call_id) { tool_call_id }
      msg.define_singleton_method(:is_error) { false }
      msg.define_singleton_method(:tool_calls) { nil }
      msg
    end

    # Stub summarization to avoid real LLM calls
    def stub_summarization(compactor)
      compactor.define_singleton_method(:generate_summary) do |_prompt|
        "This is a test summary of the conversation."
      end
    end

    # Mock emitter for testing
    class MockEmitter
      def initialize(events_array)
        @events = events_array
      end

      def emit(event)
        @events << event
      end
    end
  end
end
