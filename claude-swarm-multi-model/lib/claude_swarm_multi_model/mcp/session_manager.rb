# frozen_string_literal: true

require "securerandom"

module ClaudeSwarmMultiModel
  module MCP
    # Manages MCP sessions for multi-model instances
    class SessionManager
      attr_reader :session_id, :messages

      def initialize
        reset!
      end

      def active?
        @active
      end

      def start_session
        @active = true
        @started_at = Time.now
      end

      def reset!
        @session_id = SecureRandom.uuid
        @messages = []
        @active = false
        @started_at = nil
        @total_tokens = {
          prompt: 0,
          completion: 0,
          total: 0
        }
      end

      def add_message(role:, content:, usage: nil)
        message = {
          role: role,
          content: content,
          timestamp: Time.now
        }

        if usage
          message[:usage] = usage
          update_token_usage(usage)
        end

        @messages << message
      end

      def message_count
        @messages.size
      end

      def total_tokens
        @total_tokens[:total]
      end

      def session_info
        {
          session_id: @session_id,
          active: @active,
          started_at: @started_at,
          message_count: message_count,
          total_tokens: @total_tokens,
          messages: @messages.map do |msg|
            {
              role: msg[:role],
              content: msg[:content].slice(0, 100) + (msg[:content].length > 100 ? "..." : ""),
              timestamp: msg[:timestamp]
            }
          end
        }
      end

      private

      def update_token_usage(usage)
        @total_tokens[:prompt] += usage[:prompt_tokens] || 0
        @total_tokens[:completion] += usage[:completion_tokens] || 0
        @total_tokens[:total] += usage[:total_tokens] || 0
      end
    end
  end
end
