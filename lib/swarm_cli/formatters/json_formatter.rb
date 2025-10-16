# frozen_string_literal: true

module SwarmCLI
  module Formatters
    # JsonFormatter streams JSON log entries in real-time for consumption by scripts.
    # Each log entry is output as a single line of JSON (newline-delimited JSON).
    #
    # No colors, no spinners, no animations - just pure structured data.
    class JsonFormatter
      def initialize(output: $stdout)
        @output = output
      end

      # Called when swarm execution starts
      #
      # Note: SwarmSDK now automatically emits swarm_start as a log event,
      # so we don't emit it here to avoid duplicates. The swarm_start event
      # will flow through on_log() from the SwarmSDK event stream.
      def on_start(config_path:, swarm_name:, lead_agent:, prompt:)
        # SwarmSDK emits swarm_start automatically - no need to emit here
      end

      # Called for each log entry from SwarmSDK
      def on_log(entry)
        emit(entry)
      end

      # Called when swarm execution completes successfully
      #
      # No action needed - SwarmSDK's swarm_stop event already contains all necessary
      # information (content, last_agent, duration, metrics, etc.)
      def on_success(result:)
        # SwarmSDK emits swarm_stop automatically with complete information
      end

      # Called when swarm execution fails
      #
      # No action needed - SwarmSDK's swarm_stop event already contains error information
      def on_error(error:, duration: nil)
        # SwarmSDK emits swarm_stop automatically with error information
      end

      private

      def emit(data)
        @output.puts(data.to_json)
        @output.flush
      end
    end
  end
end
