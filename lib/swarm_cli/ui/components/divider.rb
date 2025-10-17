# frozen_string_literal: true

module SwarmCLI
  module UI
    module Components
      # Divider rendering for visual separation
      # Only horizontal lines - no side borders per design constraint
      class Divider
        def initialize(pastel:, terminal_width: 80)
          @pastel = pastel
          @terminal_width = terminal_width
        end

        # Full-width divider line
        # ────────────────────────────────────────────────────────────
        def full(char: "─", color: :dim)
          @pastel.public_send(color, char * @terminal_width)
        end

        # Event separator (dotted, indented)
        #   ····························································
        def event(indent: 0, char: "·")
          prefix = "  " * indent
          line = char * 60
          "#{prefix}#{@pastel.dim(line)}"
        end

        # Section divider with centered label
        # ───────── Section Name ─────────
        def section(label, char: "─", color: :dim)
          label_width = label.length + 2 # Add spaces around label
          total_line_width = @terminal_width
          side_width = (total_line_width - label_width) / 2

          left = char * side_width
          right = char * (total_line_width - label_width - side_width)

          @pastel.public_send(color, "#{left} #{label} #{right}")
        end

        # Top border only (no sides)
        # ────────────────────────────────────────────────────────────
        # Content here
        def top(char: "─", color: :dim)
          @pastel.public_send(color, char * @terminal_width)
        end

        # Bottom border only (no sides)
        # Content here
        # ────────────────────────────────────────────────────────────
        def bottom(char: "─", color: :dim)
          @pastel.public_send(color, char * @terminal_width)
        end
      end
    end
  end
end
