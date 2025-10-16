# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class PanelTest < Minitest::Test
  def setup
    @pastel = Pastel.new(enabled: false)
    @panel = SwarmCLI::UI::Components::Panel.new(pastel: @pastel)
  end

  def test_render_warning_panel
    result = @panel.render(
      type: :warning,
      title: "Warning Title",
      lines: ["Line 1", "Line 2"],
      indent: 0,
    )

    assert_includes(result, "Warning Title")
    assert_includes(result, "Line 1")
    assert_includes(result, "Line 2")
    assert_includes(result, SwarmCLI::UI::Icons::WARNING)
  end

  def test_render_error_panel
    result = @panel.render(
      type: :error,
      title: "Error Title",
      lines: ["Error message"],
      indent: 0,
    )

    assert_includes(result, "Error Title")
    assert_includes(result, "Error message")
    assert_includes(result, SwarmCLI::UI::Icons::ERROR)
  end

  def test_render_info_panel
    result = @panel.render(
      type: :info,
      title: "Info Title",
      lines: ["Info message"],
      indent: 0,
    )

    assert_includes(result, "Info Title")
    assert_includes(result, "Info message")
    assert_includes(result, SwarmCLI::UI::Icons::INFO)
  end

  def test_render_success_panel
    result = @panel.render(
      type: :success,
      title: "Success Title",
      lines: ["Success message"],
      indent: 0,
    )

    assert_includes(result, "Success Title")
    assert_includes(result, "Success message")
    assert_includes(result, SwarmCLI::UI::Icons::SUCCESS)
  end

  def test_render_with_indentation
    result = @panel.render(
      type: :info,
      title: "Title",
      lines: ["Line"],
      indent: 2,
    )

    # Should have indentation (4 spaces for indent level 2)
    assert_match(/^    /, result.split("\n").first)
  end

  def test_render_with_multiple_lines
    result = @panel.render(
      type: :info,
      title: "Title",
      lines: ["Line 1", "Line 2", "Line 3"],
      indent: 0,
    )

    assert_includes(result, "Line 1")
    assert_includes(result, "Line 2")
    assert_includes(result, "Line 3")
  end

  def test_render_compact_warning
    result = @panel.render_compact(
      type: :warning,
      message: "Warning message",
      indent: 0,
    )

    assert_includes(result, "Warning message")
    assert_includes(result, SwarmCLI::UI::Icons::WARNING)
  end

  def test_render_compact_error
    result = @panel.render_compact(
      type: :error,
      message: "Error message",
      indent: 0,
    )

    assert_includes(result, "Error message")
    assert_includes(result, SwarmCLI::UI::Icons::ERROR)
  end

  def test_render_compact_with_indentation
    result = @panel.render_compact(
      type: :info,
      message: "Message",
      indent: 2,
    )

    # Should start with indentation
    assert_match(/^    /, result)
  end

  def test_render_defaults_to_info_for_unknown_type
    result = @panel.render(
      type: :unknown_type,
      title: "Title",
      lines: ["Line"],
      indent: 0,
    )

    # Should use info icon as fallback
    assert_includes(result, SwarmCLI::UI::Icons::INFO)
  end
end
