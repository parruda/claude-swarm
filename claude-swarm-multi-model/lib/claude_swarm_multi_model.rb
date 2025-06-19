# frozen_string_literal: true

require_relative "claude_swarm_multi_model/version"
require_relative "claude_swarm_multi_model/provider_registry"
require_relative "claude_swarm_multi_model/config_validator"
require_relative "claude_swarm_multi_model/providers/registry"

# Only load MCP components if fast_mcp is available
if ENV["RACK_ENV"] == "test" || ENV["RAILS_ENV"] == "test" || $0.include?("rake")
  require_relative "claude_swarm_multi_model/test_mcp"
else
  begin
    require "fast_mcp_annotations"
    require_relative "claude_swarm_multi_model/mcp"
  rescue LoadError
    # MCP components are optional
  end
end

# Load appropriate CLI based on environment
if ENV["RACK_ENV"] == "test" || ENV["RAILS_ENV"] == "test" || $0.include?("rake")
  require_relative "claude_swarm_multi_model/test_cli"
else
  require_relative "claude_swarm_multi_model/cli"
end

# Only load extension if claude_swarm is available
if defined?(ClaudeSwarm) || $LOAD_PATH.any? { |path| File.exist?(File.join(path, "claude_swarm.rb")) }
  require_relative "claude_swarm_multi_model/extension"
end

module ClaudeSwarmMultiModel
  class Error < StandardError; end

  # Main entry point for the extension
  def self.setup
    Extension.register!
  end
end

# Auto-register when the gem is loaded (only if ClaudeSwarm is available)
ClaudeSwarmMultiModel.setup if defined?(ClaudeSwarm)
