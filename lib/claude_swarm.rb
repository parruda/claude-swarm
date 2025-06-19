# frozen_string_literal: true

require_relative "claude_swarm/version"
require_relative "claude_swarm/extensions"
require_relative "claude_swarm/cli"
require_relative "claude_swarm/configuration"
require_relative "claude_swarm/mcp_generator"
require_relative "claude_swarm/orchestrator"
require_relative "claude_swarm/claude_code_executor"
require_relative "claude_swarm/claude_mcp_server"
require_relative "claude_swarm/session_path"
require_relative "claude_swarm/session_info_tool"
require_relative "claude_swarm/reset_session_tool"
require_relative "claude_swarm/task_tool"
require_relative "claude_swarm/process_tracker"

module ClaudeSwarm
  class Error < StandardError; end

  # Load extensions after all core classes are defined
  Extensions.load_extensions
end
