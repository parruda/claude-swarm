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
  #   # During execution, LogStream calls emit
  #   LogCollector.emit(type: "user_prompt", agent: :backend)
  #
  #   # After execution, reset for next use
  #   LogCollector.reset!
  #
  module LogCollector
    class << self
      # Register a callback to receive log events
      #
      # @yield [Hash] Log event entry
      def on_log(&block)
        @callbacks ||= []
        @callbacks << block
      end

      # Emit an event to all registered callbacks
      #
      # @param entry [Hash] Log event entry
      # @return [void]
      def emit(entry)
        Array(@callbacks).each do |callback|
          callback.call(entry)
        end
      end

      # Reset the collector (clears callbacks for next execution)
      #
      # @return [void]
      def reset!
        @callbacks = []
      end
    end
  end
end
