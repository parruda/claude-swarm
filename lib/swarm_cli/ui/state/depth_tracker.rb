# frozen_string_literal: true

module SwarmCLI
  module UI
    module State
      # Tracks agent depth for hierarchical indentation display
      class DepthTracker
        def initialize
          @depths = {}
          @seen_agents = []
        end

        # Get indentation depth for agent
        def get(agent_name)
          @depths[agent_name] ||= calculate_depth(agent_name)
        end

        # Get indent string for agent
        def indent(agent_name, char: "  ")
          char * get(agent_name)
        end

        # Reset tracker (for testing)
        def reset
          @depths.clear
          @seen_agents.clear
        end

        private

        def calculate_depth(agent_name)
          @seen_agents << agent_name unless @seen_agents.include?(agent_name)

          # First agent is depth 0, all others are depth 1
          @seen_agents.size == 1 ? 0 : 1
        end
      end
    end
  end
end
