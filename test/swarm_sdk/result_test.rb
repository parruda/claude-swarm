# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ResultTest < Minitest::Test
    def test_initialization_with_all_parameters
      result = Result.new(
        content: "Task completed",
        agent: "backend",
        cost: 0.05,
        tokens: { input: 100, output: 50 },
        duration: 2.5,
        logs: [{ type: "test" }],
        error: StandardError.new("Test error"),
        metadata: { session_id: "123" },
      )

      assert_equal("Task completed", result.content)
      assert_equal("backend", result.agent)
      assert_in_delta(0.05, result.cost)
      assert_equal({ input: 100, output: 50 }, result.tokens)
      assert_in_delta(2.5, result.duration)
      assert_equal(1, result.logs.size)
      assert_instance_of(StandardError, result.error)
      assert_equal({ session_id: "123" }, result.metadata)
    end

    def test_initialization_with_minimal_parameters
      result = Result.new(agent: "test_agent")

      assert_nil(result.content)
      assert_equal("test_agent", result.agent)
      assert_in_delta(0.0, result.cost)
      assert_empty(result.tokens)
      assert_in_delta(0.0, result.duration)
      assert_empty(result.logs)
      assert_nil(result.error)
      assert_empty(result.metadata)
    end

    def test_attr_readers
      result = Result.new(agent: "test")

      assert_respond_to(result, :content)
      assert_respond_to(result, :agent)
      assert_respond_to(result, :cost)
      assert_respond_to(result, :tokens)
      assert_respond_to(result, :duration)
      assert_respond_to(result, :logs)
      assert_respond_to(result, :error)
      assert_respond_to(result, :metadata)
    end

    def test_success_with_no_error
      result = Result.new(agent: "test", error: nil)

      assert_predicate(result, :success?)
    end

    def test_success_with_error
      result = Result.new(agent: "test", error: StandardError.new("Failed"))

      refute_predicate(result, :success?)
    end

    def test_failure_with_error
      result = Result.new(agent: "test", error: StandardError.new("Failed"))

      assert_predicate(result, :failure?)
    end

    def test_failure_with_no_error
      result = Result.new(agent: "test", error: nil)

      refute_predicate(result, :failure?)
    end

    def test_to_h_with_success
      result = Result.new(
        content: "Response",
        agent: "backend",
        cost: 0.02,
        tokens: { input: 50, output: 25 },
        duration: 1.2,
        metadata: { key: "value" },
      )

      hash = result.to_h

      assert_equal("Response", hash[:content])
      assert_equal("backend", hash[:agent])
      assert_in_delta(0.02, hash[:cost])
      assert_equal({ input: 50, output: 25 }, hash[:tokens])
      assert_in_delta(1.2, hash[:duration])
      assert(hash[:success])
      assert_nil(hash[:error])
      assert_equal({ key: "value" }, hash[:metadata])
    end

    def test_to_h_with_failure
      error = StandardError.new("Something went wrong")
      result = Result.new(
        agent: "backend",
        error: error,
      )

      hash = result.to_h

      refute(hash[:success])
      assert_equal("Something went wrong", hash[:error])
    end

    def test_to_h_compacts_nil_values
      result = Result.new(
        content: nil,
        agent: "test",
        cost: 0.0,
        tokens: {},
        duration: 0.0,
        logs: [],
        error: nil,
        metadata: {},
      )

      hash = result.to_h

      # Has non-nil values
      assert(hash.key?(:agent))
      assert(hash.key?(:cost))
      assert(hash.key?(:tokens))
      assert(hash.key?(:duration))
      assert(hash.key?(:success))
      assert(hash.key?(:metadata))

      # Compacts nil values
      refute(hash.key?(:content))
      refute(hash.key?(:error))
    end

    def test_to_json
      result = Result.new(
        content: "Test response",
        agent: "backend",
        cost: 0.01,
      )

      json_string = result.to_json

      assert_instance_of(String, json_string)

      parsed = JSON.parse(json_string)

      assert_equal("Test response", parsed["content"])
      assert_equal("backend", parsed["agent"])
      assert_in_delta(0.01, parsed["cost"])
      assert(parsed["success"])
    end

    def test_total_cost_with_no_logs
      result = Result.new(agent: "test", logs: [])

      assert_in_delta(0.0, result.total_cost)
    end

    def test_total_cost_with_logs
      # New calculation: last input_cost + sum of all output_costs
      # Step 1: input=$0.01, output=$0.002
      # Step 2: input=$0.015, output=$0.003
      # Step 3: input=$0.02, output=$0.005
      # Expected: $0.02 (last input) + $0.01 (sum of outputs) = $0.03
      logs = [
        { type: "agent_step", usage: { total_cost: 0.012, input_cost: 0.01, output_cost: 0.002 } },
        { type: "agent_step", usage: { total_cost: 0.018, input_cost: 0.015, output_cost: 0.003 } },
        { type: "agent_stop", usage: { total_cost: 0.025, input_cost: 0.02, output_cost: 0.005 } },
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_in_delta(0.03, result.total_cost)
    end

    def test_total_cost_with_missing_usage
      # New calculation: last input_cost + sum of all output_costs
      # Step 1: input=$0.008, output=$0.002
      # Step 2: (no usage)
      # Step 3: (no usage)
      # Step 4: input=$0.015, output=$0.005
      # Expected: $0.015 (last input) + $0.007 (sum of outputs) = $0.022
      logs = [
        { type: "agent_stop", usage: { total_cost: 0.01, input_cost: 0.008, output_cost: 0.002 } },
        { type: "tool_call" }, # No usage field
        { type: "agent_stop" }, # No usage field
        { type: "agent_stop", usage: { total_cost: 0.02, input_cost: 0.015, output_cost: 0.005 } },
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_in_delta(0.022, result.total_cost)
    end

    def test_total_tokens_with_no_logs
      result = Result.new(agent: "test", logs: [])

      assert_equal(0, result.total_tokens)
    end

    def test_total_tokens_with_logs
      # New calculation: Use cumulative_total_tokens from last entry
      # Each step's total_tokens includes full conversation history (overcounting)
      # cumulative_total_tokens properly tracks the real usage
      logs = [
        { type: "agent_step", usage: { total_tokens: 100, cumulative_total_tokens: 100 } },
        { type: "agent_step", usage: { total_tokens: 200, cumulative_total_tokens: 250 } },
        { type: "agent_stop", usage: { total_tokens: 300, cumulative_total_tokens: 450 } },
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_equal(450, result.total_tokens)
    end

    def test_total_tokens_with_missing_usage
      # New calculation: Use cumulative_total_tokens from last entry with usage
      logs = [
        { type: "agent_stop", usage: { total_tokens: 100, cumulative_total_tokens: 100 } },
        { type: "tool_call" }, # No usage field
        { type: "agent_stop", usage: { total_tokens: 50, cumulative_total_tokens: 150 } },
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_equal(150, result.total_tokens)
    end

    def test_agents_involved_with_no_logs
      result = Result.new(agent: "test", logs: [])

      assert_empty(result.agents_involved)
    end

    def test_agents_involved_with_single_agent
      logs = [
        { type: "agent_stop", agent: "backend" },
        { type: "tool_call", agent: "backend" },
        { type: "agent_stop", agent: "backend" },
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_equal([:backend], result.agents_involved)
    end

    def test_agents_involved_with_multiple_agents
      logs = [
        { type: "agent_stop", agent: "lead" },
        { type: "tool_call", agent: "backend" },
        { type: "agent_stop", agent: "backend" },
        { type: "tool_call", agent: "frontend" },
        { type: "agent_stop", agent: "frontend" },
        { type: "agent_stop", agent: "backend" }, # Duplicate
      ]
      result = Result.new(agent: "test", logs: logs)

      agents = result.agents_involved

      assert_equal(3, agents.size)
      assert_includes(agents, :lead)
      assert_includes(agents, :backend)
      assert_includes(agents, :frontend)
    end

    def test_agents_involved_with_missing_agent_field
      logs = [
        { type: "agent_stop", agent: "backend" },
        { type: "tool_call" }, # No agent field
        { type: "agent_stop", agent: "frontend" },
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_equal([:backend, :frontend], result.agents_involved)
    end

    def test_agents_involved_returns_symbols
      logs = [
        { type: "agent_stop", agent: "backend" },
        { type: "agent_stop", agent: :frontend }, # Already a symbol
      ]
      result = Result.new(agent: "test", logs: logs)

      agents = result.agents_involved

      assert_instance_of(Symbol, agents[0])
      assert_instance_of(Symbol, agents[1])
    end

    def test_llm_requests_with_no_logs
      result = Result.new(agent: "test", logs: [])

      assert_equal(0, result.llm_requests)
    end

    def test_llm_requests_with_only_llm_responses
      logs = [
        { type: "user_prompt" },
        { type: "agent_stop" }, # LLM responds with final answer
        { type: "user_prompt" },
        { type: "agent_stop" },
        { type: "user_prompt" },
        { type: "agent_stop" },
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_equal(3, result.llm_requests)
    end

    def test_llm_requests_with_mixed_log_types
      logs = [
        { type: "user_prompt" },
        { type: "agent_step" }, # LLM responds with tool calls
        { type: "tool_call" },
        { type: "tool_result" },
        { type: "agent_step" }, # LLM responds with more tool calls
        { type: "tool_call" },
        { type: "tool_result" },
        { type: "agent_stop" }, # LLM responds with final answer
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_equal(3, result.llm_requests) # 2 agent_step + 1 agent_stop
    end

    def test_tool_calls_count_with_no_logs
      result = Result.new(agent: "test", logs: [])

      assert_equal(0, result.tool_calls_count)
    end

    def test_tool_calls_count_with_only_tool_calls
      logs = [
        { type: "tool_call" },
        { type: "tool_call" },
        { type: "tool_call" },
        { type: "tool_call" },
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_equal(4, result.tool_calls_count)
    end

    def test_tool_calls_count_with_mixed_log_types
      logs = [
        { type: "user_prompt" },
        { type: "tool_call" },
        { type: "agent_stop" },
        { type: "tool_call" },
        { type: "tool_result" },
        { type: "tool_call" },
        { type: "agent_stop" },
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_equal(3, result.tool_calls_count)
    end

    def test_log_aggregation_methods_work_together
      # New calculation with realistic cumulative tracking:
      # Tokens: Use cumulative_total_tokens from last entry (470)
      # Cost: Last input_cost (0.012) + sum of all output_costs (0.001 + 0.002 + 0.003 + 0.004 + 0.005 = 0.015) = 0.027
      logs = [
        { type: "user_prompt", agent: "lead" },
        { type: "agent_step", agent: "lead", usage: { total_cost: 0.005, input_cost: 0.004, output_cost: 0.001, total_tokens: 50, cumulative_total_tokens: 50 } },
        { type: "tool_call", agent: "backend" },
        { type: "tool_result", agent: "backend" },
        { type: "agent_step", agent: "lead", usage: { total_cost: 0.007, input_cost: 0.005, output_cost: 0.002, total_tokens: 100, cumulative_total_tokens: 130 } },
        { type: "tool_call", agent: "frontend" },
        { type: "tool_result", agent: "frontend" },
        { type: "agent_stop", agent: "lead", usage: { total_cost: 0.01, input_cost: 0.007, output_cost: 0.003, total_tokens: 150, cumulative_total_tokens: 230 } },
        { type: "agent_stop", agent: "backend", usage: { total_cost: 0.014, input_cost: 0.01, output_cost: 0.004, total_tokens: 200, cumulative_total_tokens: 350 } },
        { type: "agent_stop", agent: "frontend", usage: { total_cost: 0.017, input_cost: 0.012, output_cost: 0.005, total_tokens: 240, cumulative_total_tokens: 470 } },
      ]
      result = Result.new(agent: "test", logs: logs)

      assert_in_delta(0.027, result.total_cost) # 0.012 (last input) + 0.015 (sum outputs)
      assert_equal(470, result.total_tokens) # Last cumulative_total_tokens
      assert_equal([:lead, :backend, :frontend], result.agents_involved)
      assert_equal(5, result.llm_requests) # 2 agent_step + 3 agent_stop
      assert_equal(2, result.tool_calls_count)
    end
  end
end
