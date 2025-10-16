# frozen_string_literal: true

module SwarmSDK
  module Hooks
    # Rich context object passed to hook callbacks
    #
    # Provides hooks with comprehensive access to:
    # - Agent information (name, definition)
    # - Tool call details (for tool-related events)
    # - Delegation details (for delegation events)
    # - Swarm context (access to other agents, configuration)
    # - Metadata (arbitrary additional data)
    #
    # The context is read-write, allowing hooks to modify data
    # (e.g., add metadata, modify tool parameters).
    #
    # @example Access tool call information
    #   context.tool_call.name  # => "Write"
    #   context.tool_call.parameters  # => { file_path: "...", content: "..." }
    #
    # @example Modify metadata
    #   context.metadata[:validated] = true
    #   context.metadata[:validation_time] = Time.now
    #
    # @example Check event type
    #   if context.tool_event?
    #     validate_tool_call(context.tool_call)
    #   end
    class Context
      attr_reader :event, :agent_name, :agent_definition, :swarm, :metadata
      attr_accessor :tool_call, :tool_result, :delegation_target, :delegation_result

      # @param event [Symbol] The event type triggering this hook
      # @param agent_name [String, Symbol] Name of the agent
      # @param agent_definition [SwarmSDK::AgentDefinition, nil] Agent's configuration
      # @param swarm [SwarmSDK::Swarm, nil] Reference to the swarm (if available)
      # @param tool_call [ToolCall, nil] Tool call object (for tool events)
      # @param tool_result [ToolResult, nil] Tool result (for post_tool_use)
      # @param delegation_target [String, Symbol, nil] Target agent name (for delegation events)
      # @param delegation_result [Object, nil] Result from delegation (for post_delegation)
      # @param metadata [Hash] Additional metadata
      def initialize(
        event:,
        agent_name:,
        agent_definition: nil,
        swarm: nil,
        tool_call: nil,
        tool_result: nil,
        delegation_target: nil,
        delegation_result: nil,
        metadata: {}
      )
        @event = event
        @agent_name = agent_name
        @agent_definition = agent_definition
        @swarm = swarm
        @tool_call = tool_call
        @tool_result = tool_result
        @delegation_target = delegation_target
        @delegation_result = delegation_result
        @metadata = metadata
      end

      # Check if this is a tool-related event
      #
      # @return [Boolean] true if event is pre_tool_use or post_tool_use
      def tool_event?
        [:pre_tool_use, :post_tool_use].include?(@event)
      end

      # Check if this is a delegation-related event
      #
      # @return [Boolean] true if event is pre_delegation or post_delegation
      def delegation_event?
        [:pre_delegation, :post_delegation].include?(@event)
      end

      # Get tool name (convenience method)
      #
      # @return [String, nil] Tool name or nil if not a tool event
      def tool_name
        tool_call&.name
      end

      # Create a copy of this context with modified attributes
      #
      # Useful for chaining hooks that need to pass modified context
      # to subsequent hooks.
      #
      # @param attributes [Hash] Attributes to override
      # @return [Context] New context with modified attributes
      def with(**attributes)
        Context.new(
          event: attributes[:event] || @event,
          agent_name: attributes[:agent_name] || @agent_name,
          agent_definition: attributes[:agent_definition] || @agent_definition,
          swarm: attributes[:swarm] || @swarm,
          tool_call: attributes[:tool_call] || @tool_call,
          tool_result: attributes[:tool_result] || @tool_result,
          delegation_target: attributes[:delegation_target] || @delegation_target,
          delegation_result: attributes[:delegation_result] || @delegation_result,
          metadata: attributes[:metadata] || @metadata.dup,
        )
      end

      # Convert to hash for logging and debugging
      #
      # @return [Hash] Simplified hash representation of context
      def to_h
        {
          event: @event,
          agent_name: @agent_name,
          tool_name: tool_name,
          delegation_target: @delegation_target,
          metadata: @metadata,
        }
      end

      # Convenience methods for creating Results
      # These allow hooks to use `halt("message")` instead of `SwarmSDK::Hooks::Result.halt("message")`

      # Halt the current operation and return a message
      #
      # @param message [String] Message to return
      # @return [Result] Halt result
      def halt(message)
        Result.halt(message)
      end

      # Replace the current result with a custom value
      #
      # @param value [Object] Replacement value
      # @return [Result] Replace result
      def replace(value)
        Result.replace(value)
      end

      # Reprompt the agent with a new prompt
      #
      # @param prompt [String] New prompt
      # @return [Result] Reprompt result
      def reprompt(prompt)
        Result.reprompt(prompt)
      end

      # Finish the current agent's execution with a final message
      #
      # @param message [String] Final message from the agent
      # @return [Result] Finish agent result
      def finish_agent(message)
        Result.finish_agent(message)
      end

      # Finish the entire swarm execution with a final message
      #
      # @param message [String] Final message from the swarm
      # @return [Result] Finish swarm result
      def finish_swarm(message)
        Result.finish_swarm(message)
      end

      # Enter an interactive debugging breakpoint
      #
      # This method:
      # 1. Emits a breakpoint_enter event (formatters can pause spinners)
      # 2. Opens binding.irb for interactive debugging
      # 3. Emits a breakpoint_exit event (formatters can resume spinners)
      #
      # @example Use in a hook
      #   hook(:pre_delegation) do |ctx|
      #     ctx.breakpoint  # Pause execution and inspect context
      #   end
      #
      # @return [void]
      def breakpoint
        # Emit breakpoint_enter event
        LogStream.emit(
          type: "breakpoint_enter",
          agent: @agent_name,
          event: @event,
          timestamp: Time.now.utc.iso8601,
        )

        # Enter interactive debugging
        binding.irb # rubocop:disable Lint/Debugger

        # Emit breakpoint_exit event
        LogStream.emit(
          type: "breakpoint_exit",
          agent: @agent_name,
          event: @event,
          timestamp: Time.now.utc.iso8601,
        )
      end
    end
  end
end
