# frozen_string_literal: true

module ClaudeSwarm
  module Tools
    class SessionInfoTool < FastMcp::Tool
      tool_name "session_info"
      description "Get information about the current Claude session for this agent"

      arguments do
        # No arguments needed
      end

      def call
        executor = ClaudeMcpServer.executor

        {
          has_session: executor.has_session?,
          session_id: executor.session_id,
          working_directory: executor.working_directory,
        }
      end
    end
  end
end
