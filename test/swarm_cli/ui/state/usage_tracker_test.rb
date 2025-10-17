# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class UsageTrackerTest < Minitest::Test
  def setup
    @tracker = SwarmCLI::UI::State::UsageTracker.new
  end

  def test_initial_state
    assert_in_delta(0.0, @tracker.total_cost)
    assert_equal(0, @tracker.total_tokens)
    assert_equal(0, @tracker.llm_requests)
    assert_equal(0, @tracker.tool_calls)
    assert_empty(@tracker.agents)
  end

  def test_track_llm_request_increments_counter
    @tracker.track_llm_request(nil)

    assert_equal(1, @tracker.llm_requests)
  end

  def test_track_llm_request_accumulates_cost
    @tracker.track_llm_request(total_cost: 0.001)
    @tracker.track_llm_request(total_cost: 0.002)

    assert_in_delta(0.003, @tracker.total_cost)
  end

  def test_track_llm_request_accumulates_tokens
    @tracker.track_llm_request(total_tokens: 100)
    @tracker.track_llm_request(total_tokens: 200)

    assert_equal(300, @tracker.total_tokens)
  end

  def test_track_llm_request_handles_nil_usage_data
    @tracker.track_llm_request(nil)

    assert_equal(1, @tracker.llm_requests)
    assert_in_delta(0.0, @tracker.total_cost)
    assert_equal(0, @tracker.total_tokens)
  end

  def test_track_llm_request_handles_missing_cost
    @tracker.track_llm_request(total_tokens: 100)

    assert_equal(100, @tracker.total_tokens)
    assert_in_delta(0.0, @tracker.total_cost)
  end

  def test_track_llm_request_handles_missing_tokens
    @tracker.track_llm_request(total_cost: 0.005)

    assert_in_delta(0.005, @tracker.total_cost)
    assert_equal(0, @tracker.total_tokens)
  end

  def test_track_tool_call_increments_counter
    @tracker.track_tool_call

    assert_equal(1, @tracker.tool_calls)
  end

  def test_track_tool_call_multiple_times
    @tracker.track_tool_call
    @tracker.track_tool_call
    @tracker.track_tool_call

    assert_equal(3, @tracker.tool_calls)
  end

  def test_track_tool_call_stores_tool_name_by_id
    @tracker.track_tool_call(tool_call_id: "call_123", tool_name: "Read")

    assert_equal("Read", @tracker.tool_name_for("call_123"))
  end

  def test_tool_name_for_returns_nil_for_unknown_id
    result = @tracker.tool_name_for("unknown_id")

    assert_nil(result)
  end

  def test_track_agent_adds_to_set
    @tracker.track_agent(:agent1)
    @tracker.track_agent(:agent2)

    agents = @tracker.agents

    assert_includes(agents, :agent1)
    assert_includes(agents, :agent2)
  end

  def test_track_agent_deduplicates
    @tracker.track_agent(:agent1)
    @tracker.track_agent(:agent1)
    @tracker.track_agent(:agent1)

    agents = @tracker.agents

    assert_equal(1, agents.size)
    assert_includes(agents, :agent1)
  end

  def test_agents_returns_array
    @tracker.track_agent(:agent1)
    @tracker.track_agent(:agent2)

    agents = @tracker.agents

    assert_instance_of(Array, agents)
    assert_equal(2, agents.size)
  end

  def test_reset_clears_all_counters
    @tracker.track_llm_request(total_cost: 0.01, total_tokens: 100)
    @tracker.track_tool_call
    @tracker.track_agent(:agent1)

    @tracker.reset

    assert_in_delta(0.0, @tracker.total_cost)
    assert_equal(0, @tracker.total_tokens)
    assert_equal(0, @tracker.llm_requests)
    assert_equal(0, @tracker.tool_calls)
    assert_empty(@tracker.agents)
  end

  def test_reset_clears_tool_call_mapping
    @tracker.track_tool_call(tool_call_id: "call_123", tool_name: "Read")

    @tracker.reset

    assert_nil(@tracker.tool_name_for("call_123"))
  end

  def test_complex_usage_scenario
    # Track multiple LLM requests
    @tracker.track_llm_request(total_cost: 0.001, total_tokens: 500)
    @tracker.track_llm_request(total_cost: 0.002, total_tokens: 750)
    @tracker.track_llm_request(total_cost: 0.003, total_tokens: 1000)

    # Track tool calls
    @tracker.track_tool_call(tool_call_id: "call_1", tool_name: "Read")
    @tracker.track_tool_call(tool_call_id: "call_2", tool_name: "Write")
    @tracker.track_tool_call(tool_call_id: "call_3", tool_name: "Bash")

    # Track agents
    @tracker.track_agent(:agent1)
    @tracker.track_agent(:agent2)
    @tracker.track_agent(:agent1) # Duplicate

    # Verify all tracking
    assert_in_delta(0.006, @tracker.total_cost)
    assert_equal(2250, @tracker.total_tokens)
    assert_equal(3, @tracker.llm_requests)
    assert_equal(3, @tracker.tool_calls)
    assert_equal(2, @tracker.agents.size)
    assert_equal("Read", @tracker.tool_name_for("call_1"))
    assert_equal("Write", @tracker.tool_name_for("call_2"))
    assert_equal("Bash", @tracker.tool_name_for("call_3"))
  end
end
