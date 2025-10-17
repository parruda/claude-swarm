# frozen_string_literal: true

module SwarmCLI
  module UI
    module Formatters
      # Cost formatting with color coding
      class Cost
        class << self
          # Format cost with appropriate precision and color
          # Small costs: green, $0.001234
          # Medium costs: yellow, $0.1234
          # Large costs: red, $12.34
          def format(cost, pastel:)
            return pastel.dim("$0.0000") if cost.nil? || cost.zero?

            formatted = if cost < 0.01
              Kernel.format("%.6f", cost)
            elsif cost < 1.0
              Kernel.format("%.4f", cost)
            else
              Kernel.format("%.2f", cost)
            end

            if cost < 0.01
              pastel.green("$#{formatted}")
            elsif cost < 1.0
              pastel.yellow("$#{formatted}")
            else
              pastel.red("$#{formatted}")
            end
          end

          # Format cost without color (for plain text)
          def format_plain(cost)
            return "$0.0000" if cost.nil? || cost.zero?

            if cost < 0.01
              Kernel.format("$%.6f", cost)
            elsif cost < 1.0
              Kernel.format("$%.4f", cost)
            else
              Kernel.format("$%.2f", cost)
            end
          end
        end
      end
    end
  end
end
