# frozen_string_literal: true

module SwarmMemory
  module DSL
    # Extension module that injects memory DSL into SwarmSDK::Agent::Builder
    #
    # This module is included into Agent::Builder when swarm_memory is required,
    # adding the `memory` configuration method.
    module BuilderExtension
      # Configure persistent memory for this agent
      #
      # @example Interactive mode (default) - Learn and retrieve
      #   memory do
      #     directory ".swarm/agent-memory"
      #   end
      #
      # @example Retrieval mode - Read-only Q&A
      #   memory do
      #     directory "team-knowledge/"
      #     mode :retrieval
      #   end
      #
      # @example Researcher mode - Knowledge extraction
      #   memory do
      #     directory "team-knowledge/"
      #     mode :researcher
      #   end
      def memory(&block)
        @memory_config = SwarmMemory::DSL::MemoryConfig.new
        @memory_config.instance_eval(&block) if block_given?
        @memory_config
      end
    end
  end
end

# Inject memory DSL into Agent::Builder when this file is loaded
if defined?(SwarmSDK::Agent::Builder)
  SwarmSDK::Agent::Builder.include(SwarmMemory::DSL::BuilderExtension)
end
