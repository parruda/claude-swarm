# frozen_string_literal: true

module SwarmSDK
  module MCP
    class << self
      # Lazy load ruby_llm-mcp only when MCP servers are used
      def lazy_load
        return if @loaded

        require "ruby_llm/mcp"

        patch_notifications_initialize

        @loaded = true
      end

      private

      def patch_notifications_initialize
        # Add `id` when sending "notifications/initialized" message
        # https://github.com/patvice/ruby_llm-mcp/issues/65
        RubyLLM::MCP::Notifications::Initialize.class_eval do
          def call
            @coordinator.request(notification_body, add_id: true, wait_for_response: false)
          end
        end
      end
    end
  end
end
