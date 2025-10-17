# frozen_string_literal: true

module SwarmCLI
  module UI
    module State
      # Caches agent name → color assignments for consistent coloring
      class AgentColorCache
        # Professional color palette inspired by modern CLIs
        PALETTE = [
          :cyan,
          :magenta,
          :yellow,
          :blue,
          :green,
          :bright_cyan,
          :bright_magenta,
        ].freeze

        def initialize
          @cache = {}
          @next_index = 0
        end

        # Get color for agent (cached)
        def get(agent_name)
          @cache[agent_name] ||= assign_next_color
        end

        # Reset cache (for testing)
        def reset
          @cache.clear
          @next_index = 0
        end

        private

        def assign_next_color
          color = PALETTE[@next_index % PALETTE.size]
          @next_index += 1
          color
        end
      end
    end
  end
end
