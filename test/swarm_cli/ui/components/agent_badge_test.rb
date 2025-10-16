# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class AgentBadgeTest < Minitest::Test
  def setup
    @pastel = Pastel.new(enabled: false)
    @color_cache = SwarmCLI::UI::State::AgentColorCache.new
    @badge = SwarmCLI::UI::Components::AgentBadge.new(pastel: @pastel, color_cache: @color_cache)
  end

  def test_render_returns_agent_name
    result = @badge.render(:agent1)

    assert_equal("agent1", result)
  end

  def test_render_with_icon
    result = @badge.render(:agent1, icon: "🤖")

    assert_equal("🤖 agent1", result)
  end

  def test_render_caches_colors_consistently
    # Call render twice with same agent
    result1 = @badge.render(:agent1)
    result2 = @badge.render(:agent1)

    # Should be consistent (uses cache)
    assert_equal(result1, result2)
  end

  def test_render_list_with_multiple_agents
    result = @badge.render_list([:agent1, :agent2, :agent3])

    assert_includes(result, "agent1")
    assert_includes(result, "agent2")
    assert_includes(result, "agent3")
    assert_includes(result, ", ")
  end

  def test_render_list_with_custom_separator
    result = @badge.render_list([:agent1, :agent2], separator: " | ")

    assert_includes(result, " | ")
  end

  def test_render_list_empty_array
    result = @badge.render_list([])

    assert_empty(result)
  end
end
