# frozen_string_literal: true

module SwarmSDK
  class ContextCompactor
    # Metrics tracks compression statistics
    #
    # Provides detailed information about the compression operation:
    # - Message counts (before/after)
    # - Token counts (before/after)
    # - Compression ratio
    # - Time taken
    # - Summary of changes
    #
    # ## Usage
    #
    #   metrics = agent.compact_context
    #   puts metrics.summary
    #   puts "Compressed from #{metrics.original_tokens} to #{metrics.compressed_tokens} tokens"
    #   puts "Compression ratio: #{(metrics.compression_ratio * 100).round(1)}%"
    #
    class Metrics
      attr_reader :original_messages, :compressed_messages, :time_taken

      # Initialize metrics from compression operation
      #
      # @param original_messages [Array<RubyLLM::Message>] Messages before compression
      # @param compressed_messages [Array<RubyLLM::Message>] Messages after compression
      # @param time_taken [Float] Time taken in seconds
      def initialize(original_messages:, compressed_messages:, time_taken:)
        @original_messages = original_messages
        @compressed_messages = compressed_messages
        @time_taken = time_taken
      end

      # Number of messages before compression
      #
      # @return [Integer] Original message count
      def original_message_count
        @original_messages.size
      end

      # Number of messages after compression
      #
      # @return [Integer] Compressed message count
      def compressed_message_count
        @compressed_messages.size
      end

      # Number of messages removed
      #
      # @return [Integer] Messages removed
      def messages_removed
        original_message_count - compressed_message_count
      end

      # Number of checkpoint summary messages created
      #
      # @return [Integer] Checkpoint messages
      def messages_summarized
        @compressed_messages.count do |msg|
          msg.role == :system && msg.content.to_s.include?("CONVERSATION CHECKPOINT")
        end
      end

      # Estimated tokens before compression
      #
      # @return [Integer] Original token count
      def original_tokens
        @original_tokens ||= TokenCounter.estimate_messages(@original_messages)
      end

      # Estimated tokens after compression
      #
      # @return [Integer] Compressed token count
      def compressed_tokens
        @compressed_tokens ||= TokenCounter.estimate_messages(@compressed_messages)
      end

      # Number of tokens removed
      #
      # @return [Integer] Tokens removed
      def tokens_removed
        original_tokens - compressed_tokens
      end

      # Compression ratio (compressed / original)
      #
      # @return [Float] Ratio between 0.0 and 1.0
      def compression_ratio
        return 0.0 if original_tokens.zero?

        compressed_tokens.to_f / original_tokens
      end

      # Compression factor (original / compressed)
      #
      # e.g., 5.0 means compressed to 1/5th of original size
      #
      # @return [Float] Compression factor
      def compression_factor
        return 0.0 if compressed_tokens.zero?

        original_tokens.to_f / compressed_tokens
      end

      # Compression percentage
      #
      # @return [Float] Percentage of original size (0-100)
      def compression_percentage
        (compression_ratio * 100).round(2)
      end

      # Generate a human-readable summary
      #
      # @return [String] Summary text
      def summary
        <<~SUMMARY
          Context Compression Results:
          - Messages: #{original_message_count} → #{compressed_message_count} (-#{messages_removed})
          - Estimated tokens: #{original_tokens} → #{compressed_tokens} (-#{tokens_removed})
          - Compression ratio: #{compression_factor.round(1)}:1 (#{compression_percentage}%)
          - Checkpoints created: #{messages_summarized}
          - Time taken: #{time_taken.round(3)}s
        SUMMARY
      end

      # Convert metrics to hash for logging
      #
      # @return [Hash] Metrics as hash
      def to_h
        {
          original_message_count: original_message_count,
          compressed_message_count: compressed_message_count,
          messages_removed: messages_removed,
          messages_summarized: messages_summarized,
          original_tokens: original_tokens,
          compressed_tokens: compressed_tokens,
          tokens_removed: tokens_removed,
          compression_ratio: compression_ratio.round(4),
          compression_factor: compression_factor.round(2),
          compression_percentage: compression_percentage,
          time_taken: time_taken.round(3),
        }
      end
    end
  end
end
