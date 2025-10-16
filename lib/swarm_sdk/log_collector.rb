# frozen_string_literal: true

module SwarmSDK
  # LogCollector manages subscriber callbacks for log events.
  #
  # This module acts as an emitter implementation that forwards events
  # to user-registered callbacks. It's designed to be set as the LogStream
  # emitter during swarm execution.
  #
  # ## Usage
  #
  #   # Register a callback (before execution starts)
  #   LogCollector.on_log do |event|
  #     puts JSON.generate(event)
  #   end
  #
  #   # Freeze callbacks (after all registrations, before Async execution)
  #   LogCollector.freeze!
  #
  #   # During execution, LogStream calls emit
  #   LogCollector.emit(type: "user_prompt", agent: :backend)
  #
  # ## Fiber Safety
  #
  # LogCollector is fiber-safe because:
  # - All callbacks registered before Async execution starts
  # - freeze! makes @callbacks immutable
  # - emit() only reads the frozen array (no mutations)
  #
  module LogCollector
    class << self
      # Register a callback to receive log events
      #
      # Must be called before freeze! is called.
      #
      # @yield [Hash] Log event entry
      # @raise [StateError] If called after freeze!
      def on_log(&block)
        raise StateError, "Cannot register callbacks after LogCollector is frozen" if @frozen

        @callbacks ||= []
        @callbacks << block
      end

      # Emit an event to all registered callbacks
      #
      # @param entry [Hash] Log event entry
      # @return [void]
      def emit(entry)
        # Use defensive copy for fiber safety
        Array(@callbacks).each do |callback|
          callback.call(entry)
        end
      end

      # Freeze the callbacks array (call before Async execution)
      #
      # This prevents new callbacks from being registered and makes
      # the array immutable for fiber safety.
      #
      # @return [void]
      def freeze!
        @callbacks&.freeze
        @frozen = true
      end

      # Reset the collector (for test cleanup)
      #
      # @return [void]
      def reset!
        @callbacks = []
        @frozen = false
      end

      # Check if collector is frozen
      #
      # @return [Boolean]
      def frozen?
        @frozen
      end
    end
  end
end
