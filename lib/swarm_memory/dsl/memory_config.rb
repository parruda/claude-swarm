# frozen_string_literal: true

module SwarmMemory
  module DSL
    # Memory configuration for agents
    #
    # This class is injected into SwarmSDK when swarm_memory is required,
    # allowing agents to configure memory via the DSL.
    class MemoryConfig
      def initialize
        @adapter = :filesystem # Default adapter
        @directory = nil
        @mode = :assistant # Default mode
      end

      # DSL method to set/get adapter
      #
      # @param value [Symbol, nil] Adapter type
      # @return [Symbol] Current adapter
      def adapter(value = nil)
        return @adapter if value.nil?

        @adapter = value.to_sym
      end

      # DSL method to set/get directory
      #
      # @param value [String, nil] Memory directory path
      # @return [String] Current directory
      def directory(value = nil)
        return @directory if value.nil?

        @directory = value
      end

      # DSL method to set/get mode
      #
      # Modes:
      # - :assistant (default) - Read + Write, balanced for learning and retrieval
      # - :retrieval - Read-only, optimized for Q&A
      # - :researcher - All tools, optimized for knowledge extraction
      #
      # @param value [Symbol, nil] Memory mode
      # @return [Symbol] Current mode
      def mode(value = nil)
        return @mode if value.nil?

        @mode = value.to_sym
      end

      # Check if memory is enabled
      #
      # @return [Boolean] True if directory is configured
      def enabled?
        !@directory.nil?
      end
    end
  end
end
