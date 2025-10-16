# frozen_string_literal: true

module SwarmCLI
  module UI
    module State
      # Tracks cumulative usage statistics during swarm execution
      class UsageTracker
        attr_reader :total_cost, :total_tokens, :llm_requests, :tool_calls

        def initialize
          @total_cost = 0.0
          @total_tokens = 0
          @llm_requests = 0
          @tool_calls = 0
          @agents_seen = Set.new
          @recent_tool_calls = {} # tool_call_id => tool_name for matching
        end

        # Track an LLM API call
        def track_llm_request(usage_data)
          @llm_requests += 1

          if usage_data
            @total_cost += usage_data[:total_cost] || 0.0
            @total_tokens += usage_data[:total_tokens] || 0
          end
        end

        # Track a tool call
        def track_tool_call(tool_call_id: nil, tool_name: nil)
          @tool_calls += 1
          @recent_tool_calls[tool_call_id] = tool_name if tool_call_id && tool_name
        end

        # Track agent usage
        def track_agent(agent_name)
          @agents_seen.add(agent_name)
        end

        # Get list of agents seen
        def agents
          @agents_seen.to_a
        end

        # Get tool name from call ID
        def tool_name_for(tool_call_id)
          @recent_tool_calls[tool_call_id]
        end

        # Reset all counters (for testing)
        def reset
          @total_cost = 0.0
          @total_tokens = 0
          @llm_requests = 0
          @tool_calls = 0
          @agents_seen.clear
          @recent_tool_calls.clear
        end
      end
    end
  end
end
