# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ContextCompactor
    class MetricsTest < Minitest::Test
      def setup
        @original_messages = create_messages(100)
        @compressed_messages = create_messages(30)
        @time_taken = 2.5

        @metrics = Metrics.new(
          original_messages: @original_messages,
          compressed_messages: @compressed_messages,
          time_taken: @time_taken,
        )
      end

      def test_original_message_count
        assert_equal(100, @metrics.original_message_count)
      end

      def test_compressed_message_count
        assert_equal(30, @metrics.compressed_message_count)
      end

      def test_messages_removed
        assert_equal(70, @metrics.messages_removed)
      end

      def test_messages_summarized_counts_checkpoints
        # Add a checkpoint message
        checkpoint = create_message(:system, "[CONVERSATION CHECKPOINT - 2025-01-01T00:00:00Z]\nSummary here")
        compressed_with_checkpoint = @compressed_messages + [checkpoint]

        metrics = Metrics.new(
          original_messages: @original_messages,
          compressed_messages: compressed_with_checkpoint,
          time_taken: @time_taken,
        )

        assert_equal(1, metrics.messages_summarized)
      end

      def test_messages_summarized_is_zero_without_checkpoints
        assert_equal(0, @metrics.messages_summarized)
      end

      def test_original_tokens
        tokens = @metrics.original_tokens

        assert_operator(tokens, :>, 0)
      end

      def test_compressed_tokens
        tokens = @metrics.compressed_tokens

        assert_operator(tokens, :>, 0)
      end

      def test_tokens_removed
        removed = @metrics.tokens_removed

        assert_operator(removed, :>, 0)
        assert_equal(@metrics.original_tokens - @metrics.compressed_tokens, removed)
      end

      def test_compression_ratio
        ratio = @metrics.compression_ratio

        # Ratio should be between 0 and 1
        assert_operator(ratio, :>, 0)
        assert_operator(ratio, :<=, 1.0)

        # Should be compressed_tokens / original_tokens
        expected = @metrics.compressed_tokens.to_f / @metrics.original_tokens

        assert_in_delta(expected, ratio, 0.001)
      end

      def test_compression_factor
        factor = @metrics.compression_factor

        # Factor should be >= 1 (original / compressed)
        assert_operator(factor, :>=, 1.0)

        # Should be original_tokens / compressed_tokens
        expected = @metrics.original_tokens.to_f / @metrics.compressed_tokens

        assert_in_delta(expected, factor, 0.001)
      end

      def test_compression_percentage
        percentage = @metrics.compression_percentage

        # Percentage should be between 0 and 100
        assert_operator(percentage, :>, 0)
        assert_operator(percentage, :<=, 100)
      end

      def test_summary_includes_key_information
        summary = @metrics.summary

        assert_includes(summary, "100 → 30")
        assert_includes(summary, "-70")
        assert_includes(summary, "2.5")
        assert_includes(summary, "Compression ratio")
      end

      def test_to_h_returns_complete_hash
        hash = @metrics.to_h

        assert_equal(100, hash[:original_message_count])
        assert_equal(30, hash[:compressed_message_count])
        assert_equal(70, hash[:messages_removed])
        assert_equal(0, hash[:messages_summarized])
        assert_operator(hash[:original_tokens], :>, 0)
        assert_operator(hash[:compressed_tokens], :>, 0)
        assert_operator(hash[:tokens_removed], :>, 0)
        assert_operator(hash[:compression_ratio], :>, 0)
        assert_operator(hash[:compression_factor], :>=, 1.0)
        assert_operator(hash[:compression_percentage], :>, 0)
        assert_in_delta(2.5, hash[:time_taken])
      end

      def test_compression_ratio_with_zero_original_tokens
        # Edge case: no original messages
        metrics = Metrics.new(
          original_messages: [],
          compressed_messages: [],
          time_taken: 0,
        )

        assert_in_delta(0.0, metrics.compression_ratio)
      end

      def test_compression_factor_with_zero_compressed_tokens
        # Edge case: all messages removed (shouldn't happen in practice)
        metrics = Metrics.new(
          original_messages: create_messages(10),
          compressed_messages: [],
          time_taken: 0,
        )

        assert_in_delta(0.0, metrics.compression_factor)
      end

      private

      # Create N mock messages
      def create_messages(count)
        count.times.map { |i| create_message(:user, "message #{i}") }
      end

      # Create a mock message
      def create_message(role, content)
        msg = Object.new
        msg.define_singleton_method(:role) { role }
        msg.define_singleton_method(:content) { content }
        msg
      end
    end
  end
end
