# frozen_string_literal: true

module SwarmMemory
  module DSL
    # Memory configuration for agents
    #
    # This class is injected into SwarmSDK when swarm_memory is required,
    # allowing agents to configure memory via the DSL.
    #
    # Supports custom adapters through options hash that gets passed through
    # to the adapter constructor.
    #
    # @example Filesystem adapter
    #   memory do
    #     adapter :filesystem
    #     directory ".swarm/memory"
    #   end
    #
    # @example Custom adapter
    #   memory do
    #     adapter :activerecord
    #     option :namespace, "my_agent"
    #     option :table_name, "memory_entries"
    #   end
    class MemoryConfig
      attr_reader :adapter_type, :adapter_options

      def initialize
        @adapter_type = :filesystem # Default adapter
        @adapter_options = {} # Options passed to adapter constructor
        @mode = :assistant # Default mode
      end

      # DSL method to set/get adapter type
      #
      # @param value [Symbol, nil] Adapter type
      # @return [Symbol] Current adapter
      def adapter(value = nil)
        return @adapter_type if value.nil?

        @adapter_type = value.to_sym
      end

      # DSL method to set adapter option (generic)
      #
      # This allows passing any option to the adapter constructor.
      #
      # @param key [Symbol] Option key
      # @param value [Object] Option value
      #
      # @example
      #   option :namespace, "my_agent"
      #   option :connection_pool_size, 5
      def option(key, value)
        @adapter_options[key.to_sym] = value
      end

      # DSL method to set/get directory (convenience for filesystem adapter)
      #
      # Equivalent to: option :directory, value
      #
      # @param value [String, nil] Memory directory path
      # @return [String] Current directory
      def directory(value = nil)
        if value.nil?
          @adapter_options[:directory]
        else
          @adapter_options[:directory] = value
        end
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
      # @return [Boolean] True if adapter is configured with required options
      def enabled?
        case @adapter_type
        when :filesystem
          !@adapter_options[:directory].nil?
        else
          # For custom adapters, assume enabled if adapter is set
          # Custom adapter will validate its own requirements
          true
        end
      end

      # Convert config to hash (for SDK plugin)
      #
      # @return [Hash] Configuration as hash
      def to_h
        {
          adapter: @adapter_type,
          mode: @mode,
          **@adapter_options,
        }
      end
    end
  end
end
