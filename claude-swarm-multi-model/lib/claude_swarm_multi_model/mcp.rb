# frozen_string_literal: true

module ClaudeSwarmMultiModel
  module Mcp
    # Wrapper module for MCP components
  end
end

# Load MCP components
require_relative "mcp/server"
require_relative "mcp/executor"
require_relative "mcp/session_manager"