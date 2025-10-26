# frozen_string_literal: true

module SwarmMemory
  module Integration
    # Configuration for agent memory
    #
    # Used by SwarmSDK to configure memory settings for agents.
    # This mirrors the MemoryConfig in SwarmSDK but lives in SwarmMemory.
    class Configuration
      def initialize
        @adapter = :filesystem
        @directory = nil
      end

      # DSL method to set/get adapter
      #
      # @param value [Symbol, String, nil] Adapter type (:filesystem, :redis, etc.)
      # @return [Symbol] Current adapter
      def adapter(value = nil)
        return @adapter if value.nil?

        @adapter = value.to_sym
      end

      # DSL method to set/get directory
      #
      # @param value [String, nil] Directory path for storage
      # @return [String, nil] Current directory
      def directory(value = nil)
        return @directory if value.nil?

        @directory = value
      end

      # Check if memory is enabled
      #
      # @return [Boolean] True if directory is set
      def enabled?
        !@directory.nil?
      end
    end
  end
end
