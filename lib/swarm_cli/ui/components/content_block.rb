# frozen_string_literal: true

module SwarmCLI
  module UI
    module Components
      # Renders multi-line content blocks with indentation
      class ContentBlock
        def initialize(pastel:)
          @pastel = pastel
        end

        # Render key-value pairs as indented block
        #   Arguments:
        #     file_path: "config.yml"
        #     mode: "read"
        def render_hash(data, indent: 0, label: nil, truncate: false, max_value_length: 300)
          return "" if data.nil? || data.empty?

          lines = []
          prefix = "  " * indent

          # Optional label
          lines << "#{prefix}#{@pastel.dim("#{label}:")}" if label

          # Render each key-value pair
          data.each do |key, value|
            formatted_value = format_value(value, truncate: truncate, max_length: max_value_length)
            lines << "#{prefix}  #{@pastel.cyan("#{key}:")} #{formatted_value}"
          end

          lines.join("\n")
        end

        # Render multi-line text with indentation
        def render_text(text, indent: 0, color: :white, truncate: false, max_lines: nil, max_chars: nil)
          return "" if text.nil? || text.empty?

          prefix = "  " * indent
          content = text

          # Strip system reminders
          content = Formatters::Text.strip_system_reminders(content)
          return "" if content.empty?

          # Apply truncation if requested
          if truncate
            content, truncation_msg = Formatters::Text.truncate(
              content,
              lines: max_lines,
              chars: max_chars,
            )
          end

          # Render lines
          lines = content.split("\n").map do |line|
            "#{prefix}  #{@pastel.public_send(color, line)}"
          end

          # Add truncation message if present
          lines << "#{prefix}  #{@pastel.dim(truncation_msg)}" if truncation_msg

          lines.join("\n")
        end

        # Render list items
        #   • Item 1
        #   • Item 2
        def render_list(items, indent: 0, bullet: UI::Icons::BULLET, color: :white)
          return "" if items.nil? || items.empty?

          prefix = "  " * indent

          items.map do |item|
            "#{prefix}  #{@pastel.public_send(color, "#{bullet} #{item}")}"
          end.join("\n")
        end

        private

        def format_value(value, truncate:, max_length:)
          case value
          when String
            format_string_value(value, truncate: truncate, max_length: max_length)
          when Array
            @pastel.dim("[#{value.join(", ")}]")
          when Hash
            formatted = value.map { |k, v| "#{k}: #{v}" }.join(", ")
            @pastel.dim("{#{formatted}}")
          when Numeric
            @pastel.white(value.to_s)
          when TrueClass, FalseClass
            @pastel.white(value.to_s)
          when NilClass
            @pastel.dim("nil")
          else
            @pastel.white(value.to_s)
          end
        end

        def format_string_value(value, truncate:, max_length:)
          return @pastel.white(value) unless truncate
          return @pastel.white(value) if value.length <= max_length

          lines = value.split("\n")

          if lines.length > 3
            # Multi-line content - show first 3 lines
            preview = lines.first(3).join("\n")
            line_info = "(#{lines.length} lines, #{value.length} chars)"
            "#{@pastel.white(preview)}\n        #{@pastel.dim("... #{line_info}")}"
          else
            # Single/few lines - character truncation
            preview = value[0...max_length]
            "#{@pastel.white(preview)}\n        #{@pastel.dim("... (#{value.length} chars)")}"
          end
        end
      end
    end
  end
end
