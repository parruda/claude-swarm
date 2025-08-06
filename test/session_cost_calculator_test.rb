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

  def test_calculate_total_cost_with_cost_usd
    # Create session log with cost_usd (non-cumulative)
    File.open(@session_log_path, "w") do |f|
      # Instance 1: Multiple results with cost_usd
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)

      # Instance 2: Multiple results with cost_usd
      f.puts({
        instance: "agent2",
        event: { type: "result", cost_usd: 0.02 },
      }.to_json)
      f.puts({
        instance: "agent2",
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)

      # Instance 3: Single result
      f.puts({
        instance: "agent3",
        event: { type: "result", cost_usd: 0.03 },
      }.to_json)
    end

    result = ClaudeSwarm::SessionCostCalculator.calculate_total_cost(@session_log_path)

    # Total should be: 0.15 (sum from agent1) + 0.07 (sum from agent2) + 0.03 (from agent3) = 0.25
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

  def test_parse_instance_hierarchy_with_cost_usd
    # Create session log with relationships and cost_usd
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
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)

      # Agent2 second result
      f.puts({
        instance: "agent2",
        instance_id: "agent2_123",
        calling_instance: "agent1",
        event: { type: "result", cost_usd: 0.07 },
      }.to_json)
    end

    instances = ClaudeSwarm::SessionCostCalculator.parse_instance_hierarchy(@session_log_path)

    # Agent2 should have the sum of costs (0.12)
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
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)
    end

    total = ClaudeSwarm::SessionCostCalculator.calculate_simple_total(@session_log_path)

    # Should return the sum of all costs
    assert_in_delta(0.10, total, 0.001)
  end

  def test_calculate_total_cost_with_multiple_calls
    # Create session log with multiple calls that would have been session resets
    File.open(@session_log_path, "w") do |f|
      # Multiple calls with cost_usd
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)
      # This would have been a "reset" with total_cost_usd
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.02 },
      }.to_json)
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.03 },
      }.to_json)
    end

    result = ClaudeSwarm::SessionCostCalculator.calculate_total_cost(@session_log_path)

    # Total should be sum of all: 0.05 + 0.05 + 0.05 + 0.02 + 0.03 = 0.20
    assert_in_delta(0.20, result[:total_cost], 0.001)
  end

  def test_parse_instance_hierarchy_with_multiple_calls
    # Create session log with multiple calls
    File.open(@session_log_path, "w") do |f|
      f.puts({
        instance: "agent1",
        instance_id: "agent1_123",
        event: { type: "result", cost_usd: 0.10 },
      }.to_json)
      f.puts({
        instance: "agent1",
        instance_id: "agent1_123",
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)
      f.puts({
        instance: "agent1",
        instance_id: "agent1_123",
        event: { type: "result", cost_usd: 0.02 },
      }.to_json)
    end

    instances = ClaudeSwarm::SessionCostCalculator.parse_instance_hierarchy(@session_log_path)

    # Total cost should be sum: 0.10 + 0.05 + 0.02 = 0.17
    assert_in_delta(0.17, instances["agent1"][:cost], 0.001)
    assert_equal(3, instances["agent1"][:calls])
  end

  def test_main_instance_token_cost_calculation
    # Create session log with main instance token usage
    File.open(@session_log_path, "w") do |f|
      # Main instance assistant message with Opus model
      f.puts({
        instance: "lead_developer",
        instance_id: "main",
        event: {
          type: "assistant",
          message: {
            type: "message",
            role: "assistant",
            content: [{ type: "text", text: "Hello!" }],
            model: "claude-opus-4-1-20250805",
            usage: {
              "input_tokens" => 4,
              "cache_creation_input_tokens" => 19783,
              "cache_read_input_tokens" => 0,
              "output_tokens" => 26,
            },
          },
        },
      }.to_json)
    end

    result = ClaudeSwarm::SessionCostCalculator.calculate_total_cost(@session_log_path)

    # Calculate expected cost for Opus model:
    # Input: 4 / 1M * $15 = $0.00006
    # Cache write: 19783 / 1M * $18.75 = $0.37093125
    # Output: 26 / 1M * $75 = $0.00195
    # Total: ~$0.37294125
    assert_in_delta(0.37294125, result[:total_cost], 0.0001)
    assert_equal(Set.new(["lead_developer"]), result[:instances_with_cost])
  end

  def test_mixed_main_and_other_instances
    # Create session log with both main instance token costs and other instance cost_usd
    File.open(@session_log_path, "w") do |f|
      # Main instance with Sonnet model
      f.puts({
        instance: "main",
        instance_id: "main",
        event: {
          type: "assistant",
          message: {
            model: "claude-3-5-sonnet-20241022",
            usage: {
              "input_tokens" => 1000,
              "output_tokens" => 500,
              "cache_read_input_tokens" => 2000,
            },
          },
        },
      }.to_json)

      # Other instance with cost_usd
      f.puts({
        instance: "worker",
        instance_id: "worker_123",
        event: { type: "result", cost_usd: 0.10 },
      }.to_json)

      # Another main instance message with Haiku
      f.puts({
        instance: "main",
        instance_id: "main",
        event: {
          type: "assistant",
          message: {
            model: "claude-3-5-haiku-20241022",
            usage: {
              "input_tokens" => 5000,
              "output_tokens" => 1000,
            },
          },
        },
      }.to_json)
    end

    result = ClaudeSwarm::SessionCostCalculator.calculate_total_cost(@session_log_path)

    # Sonnet costs: 1000/1M * $3 + 500/1M * $15 + 2000/1M * $0.30 = $0.003 + $0.0075 + $0.0006 = $0.0111
    # Haiku costs: 5000/1M * $0.80 + 1000/1M * $4 = $0.004 + $0.004 = $0.008
    # Worker: $0.10
    # Total: $0.0111 + $0.008 + $0.10 = $0.1191
    assert_in_delta(0.1191, result[:total_cost], 0.0001)
    assert_equal(Set.new(["main", "worker"]), result[:instances_with_cost])
  end

  def test_model_type_detection
    calc = ClaudeSwarm::SessionCostCalculator

    assert_equal(:opus, calc.model_type_from_name("claude-opus-4-1-20250805"))
    assert_equal(:sonnet, calc.model_type_from_name("claude-3-5-sonnet-20241022"))
    assert_equal(:haiku, calc.model_type_from_name("claude-3-5-haiku-20241022"))
    assert_nil(calc.model_type_from_name("unknown-model"))
    assert_nil(calc.model_type_from_name(nil))
  end

  def test_calculate_token_cost
    calc = ClaudeSwarm::SessionCostCalculator

    # Test Opus pricing
    usage = {
      "input_tokens" => 1_000_000,  # 1M tokens
      "output_tokens" => 100_000,   # 100k tokens
      "cache_creation_input_tokens" => 50_000,  # 50k tokens
      "cache_read_input_tokens" => 200_000,     # 200k tokens
    }

    cost = calc.calculate_token_cost(usage, "claude-opus-4-1")
    # 1M * $15 + 100k * $75 + 50k * $18.75 + 200k * $1.50 = $15 + $7.5 + $0.9375 + $0.30 = $23.7375
    assert_in_delta(23.7375, cost, 0.0001)

    # Test with nil model
    assert_in_delta(0.0, calc.calculate_token_cost(usage, nil))

    # Test with nil usage
    assert_in_delta(0.0, calc.calculate_token_cost(nil, "claude-opus-4-1"))
  end

  def test_no_double_counting_main_instance
    # Test that main instance with both token costs and result events doesn't double count
    File.open(@session_log_path, "w") do |f|
      # Main instance with token costs
      f.puts({
        instance: "lead",
        instance_id: "main",
        event: {
          type: "assistant",
          message: {
            model: "claude-opus-4-1-20250805",
            usage: {
              "input_tokens" => 1000,
              "output_tokens" => 500,
            },
          },
        },
      }.to_json)

      # Main instance with result event (should be ignored)
      f.puts({
        instance: "lead",
        instance_id: "main",
        event: { type: "result", cost_usd: 0.50 },
      }.to_json)

      # Another token cost for main
      f.puts({
        instance: "lead",
        instance_id: "main",
        event: {
          type: "assistant",
          message: {
            model: "claude-opus-4-1-20250805",
            usage: {
              "input_tokens" => 2000,
              "output_tokens" => 1000,
            },
          },
        },
      }.to_json)
    end

    result = ClaudeSwarm::SessionCostCalculator.calculate_total_cost(@session_log_path)

    # Should only count token costs, not the result event
    # First: 1000/1M * $15 + 500/1M * $75 = $0.015 + $0.0375 = $0.0525
    # Second: 2000/1M * $15 + 1000/1M * $75 = $0.03 + $0.075 = $0.105
    # Total: $0.0525 + $0.105 = $0.1575 (NOT $0.50 from result event)
    assert_in_delta(0.1575, result[:total_cost], 0.0001)
  end

  def test_multiple_instances_with_cost_usd
    # Create session log with multiple instances using cost_usd
    File.open(@session_log_path, "w") do |f|
      # Agent1 costs
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.10 },
      }.to_json)

      # Agent2 costs
      f.puts({
        instance: "agent2",
        event: { type: "result", cost_usd: 0.05 },
      }.to_json)

      # Agent1 more costs
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.03 },
      }.to_json)

      # Agent2 more costs
      f.puts({
        instance: "agent2",
        event: { type: "result", cost_usd: 0.03 },
      }.to_json)

      # Agent1 more costs
      f.puts({
        instance: "agent1",
        event: { type: "result", cost_usd: 0.03 },
      }.to_json)
    end

    result = ClaudeSwarm::SessionCostCalculator.calculate_total_cost(@session_log_path)

    # Total should be:
    # Agent1: 0.10 + 0.03 + 0.03 = 0.16
    # Agent2: 0.05 + 0.03 = 0.08
    # Total: 0.16 + 0.08 = 0.24
    assert_in_delta(0.24, result[:total_cost], 0.001)
  end
end
