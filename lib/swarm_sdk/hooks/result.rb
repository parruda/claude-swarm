# frozen_string_literal: true

module SwarmSDK
  module Hooks
    # Result object returned by hooks to control execution flow
    #
    # Hooks can return a Result to:
    # - Continue normal execution (default)
    # - Halt execution and return an error/message
    # - Replace a value (e.g., tool result, delegation result)
    # - Reprompt the agent with a new prompt
    # - Finish the current agent's execution (agent scope)
    # - Finish the entire swarm execution (swarm scope)
    #
    # @example Continue normal execution (default)
    #   SwarmSDK::Hooks::Result.continue
    #
    # @example Halt execution with error message
    #   SwarmSDK::Hooks::Result.halt("Validation failed: invalid input")
    #
    # @example Replace tool result
    #   SwarmSDK::Hooks::Result.replace("Custom tool result")
    #
    # @example Reprompt agent with modified prompt
    #   SwarmSDK::Hooks::Result.reprompt("Modified task: #{original_task}")
    #
    # @example Finish current agent with message
    #   SwarmSDK::Hooks::Result.finish_agent("Agent task completed")
    #
    # @example Finish entire swarm with message
    #   SwarmSDK::Hooks::Result.finish_swarm("All tasks complete!")
    class Result
      attr_reader :action, :value

      # Valid actions that control execution flow
      VALID_ACTIONS = [:continue, :halt, :replace, :reprompt, :finish_agent, :finish_swarm].freeze

      # @param action [Symbol] Action to take (:continue, :halt, :replace, :reprompt)
      # @param value [Object, nil] Associated value (context for :continue, message for :halt, etc.)
      def initialize(action:, value: nil)
        unless VALID_ACTIONS.include?(action)
          raise ArgumentError, "Invalid action: #{action}. Valid actions: #{VALID_ACTIONS.join(", ")}"
        end

        @action = action
        @value = value
      end

      # Check if this result indicates halting execution
      #
      # @return [Boolean] true if action is :halt
      def halt?
        @action == :halt
      end

      # Check if this result provides a replacement value
      #
      # @return [Boolean] true if action is :replace
      def replace?
        @action == :replace
      end

      # Check if this result requests reprompting
      #
      # @return [Boolean] true if action is :reprompt
      def reprompt?
        @action == :reprompt
      end

      # Check if this result continues normal execution
      #
      # @return [Boolean] true if action is :continue
      def continue?
        @action == :continue
      end

      # Check if this result finishes the current agent
      #
      # @return [Boolean] true if action is :finish_agent
      def finish_agent?
        @action == :finish_agent
      end

      # Check if this result finishes the entire swarm
      #
      # @return [Boolean] true if action is :finish_swarm
      def finish_swarm?
        @action == :finish_swarm
      end

      class << self
        # Create a result that continues normal execution
        #
        # @param context [Context, nil] Updated context (optional)
        # @return [Result] Result with continue action
        def continue(context = nil)
          new(action: :continue, value: context)
        end

        # Create a result that halts execution
        #
        # @param message [String] Error or halt message
        # @return [Result] Result with halt action
        def halt(message)
          new(action: :halt, value: message)
        end

        # Create a result that replaces a value
        #
        # @param value [Object] Replacement value
        # @return [Result] Result with replace action
        def replace(value)
          new(action: :replace, value: value)
        end

        # Create a result that reprompts the agent
        #
        # @param prompt [String] New prompt to send to agent
        # @return [Result] Result with reprompt action
        def reprompt(prompt)
          new(action: :reprompt, value: prompt)
        end

        # Create a result that finishes the current agent
        #
        # Exits the agent's chat loop and returns the message as the agent's
        # final response. If this agent was delegated to, control returns to
        # the calling agent. The swarm continues if there's more work.
        #
        # @param message [String] Final message from the agent
        # @return [Result] Result with finish_agent action
        def finish_agent(message)
          new(action: :finish_agent, value: message)
        end

        # Create a result that finishes the entire swarm
        #
        # Immediately exits the Swarm.execute() loop and returns the message
        # as the final Result#output. All agent execution stops and the user
        # receives this message.
        #
        # @param message [String] Final message from the swarm
        # @return [Result] Result with finish_swarm action
        def finish_swarm(message)
          new(action: :finish_swarm, value: message)
        end
      end
    end
  end
end
