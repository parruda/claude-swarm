# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Delegate tool for delegating tasks to other agents in the swarm
    #
    # Creates agent-specific delegation tools (e.g., DelegateTaskToBackend)
    # that allow one agent to delegate work to another agent.
    # Supports pre/post delegation hooks for customization.
    class Delegate < RubyLLM::Tool
      attr_reader :delegate_name, :delegate_target, :tool_name

      # Initialize a delegation tool
      #
      # @param delegate_name [String] Name of the delegate agent (e.g., "backend")
      # @param delegate_description [String] Description of the delegate agent
      # @param delegate_chat [AgentChat] The chat instance for the delegate agent
      # @param agent_name [Symbol, String] Name of the agent using this tool
      # @param swarm [Swarm] The swarm instance
      # @param hook_registry [Hooks::Registry] Registry for callbacks
      # @param delegating_chat [Agent::Chat, nil] The chat instance of the agent doing the delegating (for accessing hooks)
      def initialize(
        delegate_name:,
        delegate_description:,
        delegate_chat:,
        agent_name:,
        swarm:,
        hook_registry:,
        delegating_chat: nil
      )
        super()

        @delegate_name = delegate_name
        @delegate_description = delegate_description
        @delegate_chat = delegate_chat
        @agent_name = agent_name
        @swarm = swarm
        @hook_registry = hook_registry
        @delegating_chat = delegating_chat

        # Generate tool name in the expected format: DelegateTaskTo[AgentName]
        @tool_name = "DelegateTaskTo#{delegate_name.to_s.capitalize}"
        @delegate_target = delegate_name.to_s
      end

      # Override description to return dynamic string based on delegate
      def description
        "Delegate tasks to #{@delegate_name}. #{@delegate_description}"
      end

      param :task,
        type: "string",
        desc: "Task description for the agent",
        required: true

      # Override name to return custom delegation tool name
      def name
        @tool_name
      end

      # Execute delegation with pre/post hooks
      #
      # @param task [String] Task to delegate
      # @return [String] Result from delegate agent or error message
      def execute(task:)
        # Get agent-specific hooks from the delegating chat instance
        agent_hooks = if @delegating_chat&.respond_to?(:hook_agent_hooks)
          @delegating_chat.hook_agent_hooks || {}
        else
          {}
        end

        # Trigger pre_delegation callback
        context = Hooks::Context.new(
          event: :pre_delegation,
          agent_name: @agent_name,
          swarm: @swarm,
          delegation_target: @delegate_target,
          metadata: {
            tool_name: @tool_name,
            task: task,
            timestamp: Time.now.utc.iso8601,
          },
        )

        executor = Hooks::Executor.new(@hook_registry, logger: RubyLLM.logger)
        pre_agent_hooks = agent_hooks[:pre_delegation] || []
        result = executor.execute_safe(event: :pre_delegation, context: context, callbacks: pre_agent_hooks)

        # Check if callback halted or replaced the delegation
        if result.halt?
          return result.value || "Delegation halted by callback"
        elsif result.replace?
          return result.value
        end

        # Proceed with delegation
        response = @delegate_chat.ask(task)
        delegation_result = response.content

        # Trigger post_delegation callback
        post_context = Hooks::Context.new(
          event: :post_delegation,
          agent_name: @agent_name,
          swarm: @swarm,
          delegation_target: @delegate_target,
          delegation_result: delegation_result,
          metadata: {
            tool_name: @tool_name,
            task: task,
            result: delegation_result,
            timestamp: Time.now.utc.iso8601,
          },
        )

        post_agent_hooks = agent_hooks[:post_delegation] || []
        post_result = executor.execute_safe(event: :post_delegation, context: post_context, callbacks: post_agent_hooks)

        # Return modified result if callback replaces it
        if post_result.replace?
          post_result.value
        else
          delegation_result
        end
      rescue Faraday::TimeoutError, Net::ReadTimeout => e
        # Log timeout error as JSON event
        LogStream.emit(
          type: "delegation_error",
          agent: @agent_name,
          delegate_to: @tool_name,
          error_class: e.class.name,
          error_message: "Request timed out",
          backtrace: e.backtrace&.first(5) || [],
        )
        "Error: Request to #{@tool_name} timed out. The agent may be overloaded or the LLM service is not responding. Please try again or simplify the task."
      rescue Faraday::Error => e
        # Log network error as JSON event
        LogStream.emit(
          type: "delegation_error",
          agent: @agent_name,
          delegate_to: @tool_name,
          error_class: e.class.name,
          error_message: e.message,
          backtrace: e.backtrace&.first(5) || [],
        )
        "Error: Network error communicating with #{@tool_name}: #{e.class.name}. Please check connectivity and try again."
      rescue StandardError => e
        # Log unexpected error as JSON event
        backtrace_array = e.backtrace&.first(5) || []
        LogStream.emit(
          type: "delegation_error",
          agent: @agent_name,
          delegate_to: @tool_name,
          error_class: e.class.name,
          error_message: e.message,
          backtrace: backtrace_array,
        )
        # Return error string for LLM
        backtrace_str = backtrace_array.join("\n  ")
        "Error: #{@tool_name} encountered an error: #{e.class.name}: #{e.message}\nBacktrace:\n  #{backtrace_str}"
      end
    end
  end
end
