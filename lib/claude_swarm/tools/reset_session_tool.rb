# frozen_string_literal: true

module ClaudeSwarm
  module Tools
    class ResetSessionTool < FastMcp::Tool
      tool_name "reset_session"
      description "Reset the Claude session for this agent, starting fresh on the next task"

      arguments do
        # No arguments needed
      end

      def call
        executor = ClaudeMcpServer.executor
        executor.reset_session

        {
          success: true,
          message: "Session has been reset",
        }
      end
    end
  end
end
