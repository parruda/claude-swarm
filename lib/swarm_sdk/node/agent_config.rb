# frozen_string_literal: true

module SwarmSDK
  module Node
    # AgentConfig provides fluent API for configuring agents within a node
    #
    # This class enables the chainable syntax:
    #   agent(:backend).delegates_to(:tester, :database)
    #
    # @example Basic delegation
    #   agent(:backend).delegates_to(:tester)
    #
    # @example No delegation (solo agent)
    #   agent(:planner)
    class AgentConfig
      attr_reader :agent_name

      def initialize(agent_name, node_builder)
        @agent_name = agent_name
        @node_builder = node_builder
        @delegates_to = []
        @finalized = false
      end

      # Set delegation targets for this agent
      #
      # @param agent_names [Array<Symbol>] Names of agents to delegate to
      # @return [self] For method chaining
      def delegates_to(*agent_names)
        @delegates_to = agent_names.map(&:to_sym)
        finalize
        self
      end

      # Finalize agent configuration (called automatically)
      #
      # Registers this agent configuration with the parent node builder.
      # If delegates_to was never called, registers with empty delegation.
      #
      # @return [void]
      def finalize
        return if @finalized

        @node_builder.register_agent(@agent_name, @delegates_to)
        @finalized = true
      end
    end
  end
end
