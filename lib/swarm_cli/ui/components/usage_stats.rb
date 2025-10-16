# frozen_string_literal: true

module SwarmCLI
  module UI
    module Components
      # Renders usage statistics (tokens, cost, context percentage)
      class UsageStats
        def initialize(pastel:)
          @pastel = pastel
        end

        # Render usage line with all available metrics
        # 5,922 tokens │ $0.0016 │ 1.5% used, 394,078 remaining
        def render(tokens:, cost:, context_pct: nil, remaining: nil, cumulative: nil)
          parts = []

          # Token count (always shown)
          parts << "#{Formatters::Number.format(tokens)} tokens"

          # Cost (always shown if > 0)
          parts << Formatters::Cost.format(cost, pastel: @pastel) if cost > 0

          # Context tracking (if available)
          if context_pct
            colored_pct = color_context_percentage(context_pct)

            parts << if remaining
              "#{colored_pct} used, #{Formatters::Number.compact(remaining)} remaining"
            else
              "#{colored_pct} used"
            end
          elsif cumulative
            # Model doesn't have context limit, show cumulative
            parts << "#{Formatters::Number.compact(cumulative)} cumulative"
          end

          @pastel.dim(parts.join(" #{@pastel.dim("│")} "))
        end

        # Render compact stats for prompt display
        # 15.2K tokens • $0.045 • 3.8% context
        def render_compact(tokens:, cost:, context_pct: nil)
          parts = []

          parts << "#{Formatters::Number.compact(tokens)} tokens" if tokens > 0
          parts << Formatters::Cost.format_plain(cost) if cost > 0
          parts << "#{context_pct} context" if context_pct

          parts.join(" • ")
        end

        private

        def color_context_percentage(percentage_string)
          percentage = percentage_string.to_s.gsub("%", "").to_f

          color = if percentage < 50
            :green
          elsif percentage < 80
            :yellow
          else
            :red
          end

          @pastel.public_send(color, percentage_string)
        end
      end
    end
  end
end
