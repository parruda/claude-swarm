# frozen_string_literal: true

module SwarmSDK
  module MCP
    class << self
      # Lazy load ruby_llm-mcp only when MCP servers are used
      def lazy_load
        return if @loaded

        require "ruby_llm/mcp"

        @loaded = true
      end
    end
  end
end
