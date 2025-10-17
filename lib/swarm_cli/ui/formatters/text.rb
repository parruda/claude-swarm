# frozen_string_literal: true

module SwarmCLI
  module UI
    module Formatters
      # Text manipulation utilities for clean display
      class Text
        class << self
          # Strip <system-reminder> tags from content
          def strip_system_reminders(text)
            return "" if text.nil?

            text.gsub(%r{<system-reminder>.*?</system-reminder>}m, "").strip
          end

          # Truncate text to specified character/line limits
          # Returns [display_text, truncation_message]
          def truncate(text, chars: nil, lines: nil)
            return [text, nil] if text.nil? || text.empty?

            text_lines = text.split("\n")
            truncated = false
            truncation_parts = []

            # Apply line limit
            if lines && text_lines.length > lines
              text_lines = text_lines.first(lines)
              hidden_lines = text.split("\n").length - lines
              truncation_parts << "#{hidden_lines} more lines"
              truncated = true
            end

            result_text = text_lines.join("\n")

            # Apply character limit
            if chars && result_text.length > chars
              result_text = result_text[0...chars]
              hidden_chars = text.length - chars
              truncation_parts << "#{hidden_chars} more chars"
              truncated = true
            end

            truncation_msg = truncated ? "... (#{truncation_parts.join(", ")})" : nil

            [result_text, truncation_msg]
          end

          # Wrap text to specified width
          def wrap(text, width:)
            return "" if text.nil? || text.empty?

            text.split("\n").flat_map do |line|
              wrap_line(line, width)
            end.join("\n")
          end

          # Indent all lines in text
          def indent(text, level: 0, char: "  ")
            return "" if text.nil? || text.empty?

            prefix = char * level
            text.split("\n").map { |line| "#{prefix}#{line}" }.join("\n")
          end

          private

          # Word wrap a single line
          def wrap_line(line, width)
            return [line] if line.length <= width

            line.scan(/.{1,#{width}}(?:\s+|$)/).map(&:strip)
          end
        end
      end
    end
  end
end
