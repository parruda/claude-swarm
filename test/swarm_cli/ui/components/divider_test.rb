# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class DividerTest < Minitest::Test
  def setup
    @pastel = Pastel.new(enabled: false) # Disable colors for testing
    @divider = SwarmCLI::UI::Components::Divider.new(pastel: @pastel, terminal_width: 80)
  end

  def test_full_returns_line_of_terminal_width
    result = @divider.full

    assert_equal(80, result.length)
    assert_equal("─" * 80, result)
  end

  def test_full_with_custom_char
    result = @divider.full(char: "=")

    assert_equal("=" * 80, result)
  end

  def test_event_returns_dotted_line
    result = @divider.event

    assert_includes(result, "·")
  end

  def test_event_with_indentation
    result = @divider.event(indent: 2)

    assert_match(/^    /, result) # 2 indents = 4 spaces
  end

  def test_event_with_custom_char
    result = @divider.event(char: "-")

    assert_includes(result, "-")
  end

  def test_section_with_label
    result = @divider.section("Test Section")

    assert_includes(result, "Test Section")
    assert_includes(result, "─")
  end

  def test_top_returns_full_width_line
    result = @divider.top

    assert_equal(80, result.length)
  end

  def test_bottom_returns_full_width_line
    result = @divider.bottom

    assert_equal(80, result.length)
  end
end
