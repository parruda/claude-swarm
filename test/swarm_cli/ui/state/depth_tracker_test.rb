# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class DepthTrackerTest < Minitest::Test
  def setup
    @tracker = SwarmCLI::UI::State::DepthTracker.new
  end

  def test_get_returns_zero_for_first_agent
    depth = @tracker.get(:agent1)

    assert_equal(0, depth)
  end

  def test_get_returns_one_for_second_agent
    @tracker.get(:agent1)
    depth = @tracker.get(:agent2)

    assert_equal(1, depth)
  end

  def test_get_returns_one_for_all_agents_after_first
    @tracker.get(:agent1)

    depth2 = @tracker.get(:agent2)
    depth3 = @tracker.get(:agent3)
    depth4 = @tracker.get(:agent4)

    assert_equal(1, depth2)
    assert_equal(1, depth3)
    assert_equal(1, depth4)
  end

  def test_get_caches_depth_for_same_agent
    depth1 = @tracker.get(:agent1)
    depth2 = @tracker.get(:agent1)

    assert_equal(depth1, depth2)
    assert_equal(0, depth1)
  end

  def test_indent_returns_empty_string_for_depth_zero
    @tracker.get(:agent1)
    indent = @tracker.indent(:agent1)

    assert_empty(indent)
  end

  def test_indent_returns_two_spaces_for_depth_one
    @tracker.get(:agent1)
    @tracker.get(:agent2)
    indent = @tracker.indent(:agent2)

    assert_equal("  ", indent)
  end

  def test_indent_with_custom_char
    @tracker.get(:agent1)
    @tracker.get(:agent2)
    indent = @tracker.indent(:agent2, char: "\t")

    assert_equal("\t", indent)
  end

  def test_indent_multiplies_char_by_depth
    @tracker.get(:agent1)
    @tracker.get(:agent2)
    indent = @tracker.indent(:agent2, char: ">>")

    assert_equal(">>", indent)
  end

  def test_reset_clears_depths
    @tracker.get(:agent1)
    @tracker.get(:agent2)

    @tracker.reset

    # After reset, next agent should be depth 0
    depth = @tracker.get(:agent3)

    assert_equal(0, depth)
  end

  def test_reset_clears_seen_agents
    @tracker.get(:agent1)
    @tracker.get(:agent2)

    @tracker.reset

    # After reset, same agents should get depth 0 again
    depth = @tracker.get(:agent1)

    assert_equal(0, depth)
  end
end
