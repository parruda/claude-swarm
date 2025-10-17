# frozen_string_literal: true

module SwarmCLI
  module UI
    module Components
      # Renders agent names with consistent colors using cache
      class AgentBadge
        def initialize(pastel:, color_cache:)
          @pastel = pastel
          @color_cache = color_cache
        end

        # Render agent name with cached color
        # architect → "architect" (in cyan)
        def render(agent_name, icon: nil, bold: false)
          color = @color_cache.get(agent_name)
          text = icon ? "#{icon} #{agent_name}" : agent_name.to_s

          styled = @pastel.public_send(color, text)
          styled = @pastel.bold(styled) if bold

          styled
        end

        # Render agent list (comma-separated, each colored)
        # [architect, worker] → "architect, worker" (each colored differently)
        def render_list(agent_names, separator: ", ")
          agent_names.map { |name| render(name) }.join(separator)
        end
      end
    end
  end
end
