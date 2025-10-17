# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class AgentColorCacheTest < Minitest::Test
  def setup
    @cache = SwarmCLI::UI::State::AgentColorCache.new
  end

  def test_get_assigns_color_for_first_agent
    color = @cache.get(:agent1)

    assert_equal(:cyan, color)
  end

  def test_get_returns_same_color_for_same_agent
    color1 = @cache.get(:agent1)
    color2 = @cache.get(:agent1)

    assert_equal(color1, color2)
  end

  def test_get_assigns_different_colors_for_different_agents
    color1 = @cache.get(:agent1)
    color2 = @cache.get(:agent2)

    refute_equal(color1, color2)
  end

  def test_get_cycles_through_palette
    colors = []
    10.times do |i|
      colors << @cache.get(:"agent#{i}")
    end

    # Should have used colors from palette, cycling if more than palette size
    palette_size = SwarmCLI::UI::State::AgentColorCache::PALETTE.size

    assert_operator(colors.size, :>, palette_size) # Verify we tested cycling
    assert_equal(colors[0], colors[palette_size]) # First and (palette_size+1)th should match
  end

  def test_reset_clears_cache
    @cache.get(:agent1)
    @cache.get(:agent2)

    @cache.reset

    # After reset, should get first color again
    color = @cache.get(:agent3)

    assert_equal(:cyan, color) # First color in palette
  end

  def test_reset_resets_index
    # Get several colors
    3.times { |i| @cache.get(:"agent#{i}") }

    @cache.reset

    # After reset, should start from beginning
    color = @cache.get(:new_agent)

    assert_equal(:cyan, color)
  end

  def test_palette_contains_expected_colors
    palette = SwarmCLI::UI::State::AgentColorCache::PALETTE

    assert_includes(palette, :cyan)
    assert_includes(palette, :magenta)
    assert_includes(palette, :yellow)
    assert_includes(palette, :blue)
    assert_includes(palette, :green)
    assert_includes(palette, :bright_cyan)
    assert_includes(palette, :bright_magenta)
  end

  def test_palette_is_frozen
    palette = SwarmCLI::UI::State::AgentColorCache::PALETTE

    assert_predicate(palette, :frozen?)
  end
end
