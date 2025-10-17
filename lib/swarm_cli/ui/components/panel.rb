# frozen_string_literal: true

module SwarmCLI
  module UI
    module Components
      # Renders highlighted panels for warnings, info, errors
      # Uses top/bottom borders only (no sides per design constraint)
      class Panel
        TYPE_CONFIGS = {
          warning: { color: :yellow, icon: UI::Icons::WARNING },
          error: { color: :red, icon: UI::Icons::ERROR },
          info: { color: :cyan, icon: UI::Icons::INFO },
          success: { color: :green, icon: UI::Icons::SUCCESS },
        }.freeze

        def initialize(pastel:, terminal_width: 80)
          @pastel = pastel
          @terminal_width = terminal_width
        end

        # Render panel with top/bottom borders
        #
        # ⚠️  CONTEXT WARNING
        #   Context usage: 81.4% (threshold: 80%)
        #   Tokens remaining: 74,523
        #
        def render(type:, title:, lines:, indent: 0)
          config = TYPE_CONFIGS[type] || TYPE_CONFIGS[:info]
          prefix = "  " * indent

          output = []

          # Title line with icon
          icon = config[:icon]
          colored_title = @pastel.public_send(config[:color], "#{icon} #{title}")
          output << "#{prefix}#{colored_title}"

          # Content lines
          lines.each do |line|
            output << "#{prefix}  #{line}"
          end

          output << "" # Blank line after panel

          output.join("\n")
        end

        # Render compact panel (single line)
        # ⚠️  Context approaching limit (81.4%)
        def render_compact(type:, message:, indent: 0)
          config = TYPE_CONFIGS[type] || TYPE_CONFIGS[:info]
          prefix = "  " * indent

          icon = config[:icon]
          colored_msg = @pastel.public_send(config[:color], "#{icon} #{message}")

          "#{prefix}#{colored_msg}"
        end
      end
    end
  end
end
