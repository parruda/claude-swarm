# frozen_string_literal: true

module SwarmSDK
  # LogStream provides a module-level singleton for emitting log events.
  #
  # This allows any component (tools, providers, agents) to emit structured
  # log events without needing references to logger instances.
  #
  # ## Usage
  #
  #   # Emit an event from anywhere in the SDK
  #   LogStream.emit(
  #     type: "user_prompt",
  #     agent: :backend,
  #     model: "claude-sonnet-4",
  #     message_count: 5
  #   )
  #
  # ## Fiber Safety
  #
  # LogStream is fiber-safe when following this pattern:
  # 1. Set emitter BEFORE starting Async execution
  # 2. During Async execution, only emit() (reads emitter)
  # 3. Each event includes agent context for identification
  #
  # ## Testing
  #
  #   # Inject a test emitter
  #   LogStream.emitter = TestEmitter.new
  #   # ... run tests ...
  #   LogStream.reset!
  #
  module LogStream
    class << self
      # Emit a log event
      #
      # Adds timestamp and forwards to the registered emitter.
      #
      # @param data [Hash] Event data (type, agent, and event-specific fields)
      # @return [void]
      def emit(**data)
        return unless @emitter

        entry = data.merge(timestamp: Time.now.utc.iso8601).compact

        @emitter.emit(entry)
      end

      # Set the emitter (for dependency injection in tests)
      #
      # @param emitter [#emit] Object responding to emit(Hash)
      attr_accessor :emitter

      # Reset the emitter (for test cleanup)
      #
      # @return [void]
      def reset!
        @emitter = nil
      end

      # Check if logging is enabled
      #
      # @return [Boolean] true if an emitter is configured
      def enabled?
        !@emitter.nil?
      end
    end
  end
end
