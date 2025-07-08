# frozen_string_literal: true

module ClaudeSwarm
  module Tools
    class TaskTool < FastMcp::Tool
      tool_name "task"
      description "Execute a task using Claude Code. There is no description parameter."
      annotations(read_only_hint: true, open_world_hint: false, destructive_hint: false)

      arguments do
        required(:prompt).filled(:string).description("The task or question for the agent")
        optional(:new_session).filled(:bool).description("Start a new session (default: false)")
        optional(:system_prompt).filled(:string).description("Override the system prompt for this request")
        optional(:description).filled(:string).description("A description for the request")
      end

      def call(prompt:, new_session: false, system_prompt: nil, description: nil)
        executor = ClaudeMcpServer.executor
        instance_config = ClaudeMcpServer.instance_config

        options = {
          new_session: new_session,
          system_prompt: system_prompt || instance_config[:prompt],
          description: description,
        }

        # Add allowed tools from instance config
        options[:allowed_tools] = instance_config[:allowed_tools] if instance_config[:allowed_tools]&.any?

        # Add disallowed tools from instance config
        options[:disallowed_tools] = instance_config[:disallowed_tools] if instance_config[:disallowed_tools]&.any?

        # Add connections from instance config
        options[:connections] = instance_config[:connections] if instance_config[:connections]&.any?

        response = executor.execute(prompt, options)

        # Return just the result text as expected by MCP
        response["result"]
      end
    end
  end
end
