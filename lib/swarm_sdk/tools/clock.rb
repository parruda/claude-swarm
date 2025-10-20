# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Clock tool provides current date and time information
    #
    # Returns current temporal information in a consistent format.
    # Agents use this when they need to know what day/time it is.
    class Clock < RubyLLM::Tool
      description <<~DESC
        Get current date and time.

        Returns:
        - Current date (YYYY-MM-DD format)
        - Current time (HH:MM:SS format)
        - Day of week (Monday, Tuesday, etc.)
        - ISO 8601 timestamp (full datetime)

        Use this when you need to know what day it is, what time it is,
        or to store temporal information (e.g., "As of 2025-10-20...").

        No parameters needed - just call Clock() to get complete temporal information.
      DESC

      # No parameters needed

      def execute
        now = Time.now

        <<~RESULT.chomp
          Current date: #{now.strftime("%Y-%m-%d")}
          Current time: #{now.strftime("%H:%M:%S")}
          Day of week: #{now.strftime("%A")}
          ISO 8601: #{now.iso8601}
        RESULT
      end
    end
  end
end
