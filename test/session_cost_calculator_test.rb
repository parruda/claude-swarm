# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "json"

class SessionCostCalculatorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @session_log_path = File.join(@tmpdir, "session.log.json")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_calculate_total_cost_with_cumulative_costs
    # Create session log with cumulative costs
    File.open(@session_log_path, "w") do |f|
      # Instance 1: Multiple results with cumulative costs
      f.puts({
        instance: "agent1",
        event: { type: "result", total_cost_usd: 0.05 },
      }.to_json)
      f.puts({
        instance: "agent1",
        event: { type: "result", total_cost_usd: 0.10 },
      }.to_json)
      f.puts({
        instance: "agent1",
        event: { type: "result", total_cost_usd: 0.15 },
      }.to_json)

      # Instance 2: Multiple results with cumulative costs
      f.puts({
        instance: "agent2",
        event: { type: "result", total_cost_usd: 0.02 },
      }.to_json)
      f.puts({
        instance: "agent2",
        event: { type: "result", total_cost_usd: 0.07 },
      }.to_json)

      # Instance 3: Single result
      f.puts({
        instance: "agent3",
        event: { type: "result", total_cost_usd: 0.03 },
      }.to_json)
    end

    result = ClaudeSwarm::SessionCostCalculator.calculate_total_cost(@session_log_path)

    # Total should be: 0.15 (last from agent1) + 0.07 (last from agent2) + 0.03 (from agent3) = 0.25
    assert_in_delta(0.25, result[:total_cost], 0.001)
    assert_equal(Set.new(["agent1", "agent2", "agent3"]), result[:instances_with_cost])
  end

  def test_calculate_total_cost_with_no_costs
    # Create session log without cost data
    File.open(@session_log_path, "w") do |f|
      f.puts({
        instance: "agent1",
        event: { type: "request" },
      }.to_json)
      f.puts({
        instance: "agent1",
        event: { type: "assistant" },
      }.to_json)
    end

    result = ClaudeSwarm::SessionCostCalculator.calculate_total_cost(@session_log_path)

    assert_in_delta(0.0, result[:total_cost])
    assert_equal(Set.new, result[:instances_with_cost])
  end

  def test_calculate_total_cost_with_missing_file
    result = ClaudeSwarm::SessionCostCalculator.calculate_total_cost("/nonexistent/path")

    assert_in_delta(0.0, result[:total_cost])
    assert_equal(Set.new, result[:instances_with_cost])
  end

  def test_parse_instance_hierarchy_with_cumulative_costs
    # Create session log with relationships and cumulative costs
    File.open(@session_log_path, "w") do |f|
      # Agent1 calls agent2
      f.puts({
        instance: "agent2",
        instance_id: "agent2_123",
        calling_instance: "agent1",
        calling_instance_id: "agent1_456",
        event: { type: "request" },
      }.to_json)

      # Agent2 first result
      f.puts({
        instance: "agent2",
        instance_id: "agent2_123",
        calling_instance: "agent1",
        event: { type: "result", total_cost_usd: 0.05 },
      }.to_json)

      # Agent2 second result (cumulative)
      f.puts({
        instance: "agent2",
        instance_id: "agent2_123",
        calling_instance: "agent1",
        event: { type: "result", total_cost_usd: 0.12 },
      }.to_json)
    end

    instances = ClaudeSwarm::SessionCostCalculator.parse_instance_hierarchy(@session_log_path)

    # Agent2 should have the last cumulative cost (0.12), not the sum
    assert_in_delta(0.12, instances["agent2"][:cost])
    assert_equal(2, instances["agent2"][:calls])
    assert(instances["agent2"][:has_cost_data])

    # Check relationships
    assert_equal(Set.new(["agent1"]), instances["agent2"][:called_by])
    assert_equal(Set.new(["agent2"]), instances["agent1"][:calls_to])
  end

  def test_calculate_simple_total
    # Create session log
    File.open(@session_log_path, "w") do |f|
      f.puts({
        instance: "agent1",
        event: { type: "result", total_cost_usd: 0.05 },
      }.to_json)
      f.puts({
        instance: "agent1",
        event: { type: "result", total_cost_usd: 0.10 },
      }.to_json)
    end

    total = ClaudeSwarm::SessionCostCalculator.calculate_simple_total(@session_log_path)

    # Should return just the last cumulative cost
    assert_in_delta(0.10, total, 0.001)
  end
end
