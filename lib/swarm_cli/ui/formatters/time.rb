# frozen_string_literal: true

module SwarmCLI
  module UI
    module Formatters
      # Time and duration formatting utilities
      class Time
        class << self
          # Format timestamp as [HH:MM:SS]
          # Time.now → "[12:34:56]"
          def timestamp(time)
            return "" if time.nil?

            case time
            when ::Time
              time.strftime("[%H:%M:%S]")
            when String
              parsed = ::Time.parse(time)
              parsed.strftime("[%H:%M:%S]")
            else
              ""
            end
          rescue StandardError
            ""
          end

          # Format duration in human-readable form
          # 0.5 → "500ms"
          # 2.3 → "2.3s"
          # 65 → "1m 5s"
          # 3665 → "1h 1m 5s"
          def duration(seconds)
            return "0ms" if seconds.nil? || seconds.zero?

            if seconds < 1
              "#{(seconds * 1000).round}ms"
            elsif seconds < 60
              "#{seconds.round(2)}s"
            elsif seconds < 3600
              minutes = (seconds / 60).floor
              secs = (seconds % 60).round
              "#{minutes}m #{secs}s"
            else
              hours = (seconds / 3600).floor
              minutes = ((seconds % 3600) / 60).floor
              secs = (seconds % 60).round
              "#{hours}h #{minutes}m #{secs}s"
            end
          end

          # Format relative time (future enhancement)
          # Time.now - 120 → "2 minutes ago"
          def relative(time)
            return "" if time.nil?

            seconds_ago = ::Time.now - time

            case seconds_ago
            when 0...60
              "#{seconds_ago.round}s ago"
            when 60...3600
              "#{(seconds_ago / 60).round}m ago"
            when 3600...86400
              "#{(seconds_ago / 3600).round}h ago"
            else
              "#{(seconds_ago / 86400).round}d ago"
            end
          end
        end
      end
    end
  end
end
