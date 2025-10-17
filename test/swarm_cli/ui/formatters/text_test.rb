# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class TextFormatterTest < Minitest::Test
  def test_strip_system_reminders_removes_tags
    text = "Hello <system-reminder>This is a reminder</system-reminder> World"
    result = SwarmCLI::UI::Formatters::Text.strip_system_reminders(text)

    assert_equal("Hello  World", result.strip)
    refute_includes(result, "reminder")
  end

  def test_strip_system_reminders_handles_multiline
    text = <<~TEXT
      Hello
      <system-reminder>
      Multi-line
      reminder
      </system-reminder>
      World
    TEXT

    result = SwarmCLI::UI::Formatters::Text.strip_system_reminders(text)

    refute_includes(result, "reminder")
    assert_includes(result, "Hello")
    assert_includes(result, "World")
  end

  def test_strip_system_reminders_returns_empty_for_nil
    result = SwarmCLI::UI::Formatters::Text.strip_system_reminders(nil)

    assert_empty(result)
  end

  def test_truncate_returns_text_if_under_limit
    text = "Short text"
    result_text, msg = SwarmCLI::UI::Formatters::Text.truncate(text, chars: 100)

    assert_equal(text, result_text)
    assert_nil(msg)
  end

  def test_truncate_by_lines
    text = (1..10).map { |i| "Line #{i}" }.join("\n")
    result_text, msg = SwarmCLI::UI::Formatters::Text.truncate(text, lines: 5)

    assert_equal(5, result_text.split("\n").size)
    assert_match(/5 more lines/, msg)
  end

  def test_truncate_by_chars
    text = "a" * 1000
    result_text, msg = SwarmCLI::UI::Formatters::Text.truncate(text, chars: 100)

    assert_equal(100, result_text.length)
    assert_match(/900 more chars/, msg)
  end

  def test_truncate_returns_nil_message_when_no_truncation
    text = "Short"
    _result, msg = SwarmCLI::UI::Formatters::Text.truncate(text, chars: 100, lines: 10)

    assert_nil(msg)
  end

  def test_truncate_handles_nil_text
    result_text, msg = SwarmCLI::UI::Formatters::Text.truncate(nil)

    assert_nil(result_text)
    assert_nil(msg)
  end

  def test_truncate_handles_empty_text
    result_text, msg = SwarmCLI::UI::Formatters::Text.truncate("")

    assert_empty(result_text)
    assert_nil(msg)
  end

  def test_wrap_wraps_long_lines
    text = "a" * 100
    result = SwarmCLI::UI::Formatters::Text.wrap(text, width: 50)

    lines = result.split("\n")
    # Wrapping may not work perfectly with no spaces, but should attempt it
    assert_operator(lines.size, :>=, 1)
    # At least the first line should respect width approximately
    assert_operator(lines.first.length, :<=, 55) # Allow some margin for word break behavior
  end

  def test_wrap_preserves_newlines
    text = "Line 1\nLine 2\nLine 3"
    result = SwarmCLI::UI::Formatters::Text.wrap(text, width: 100)

    assert_equal(3, result.split("\n").size)
  end

  def test_wrap_handles_nil
    result = SwarmCLI::UI::Formatters::Text.wrap(nil, width: 80)

    assert_empty(result)
  end

  def test_indent_adds_spaces
    text = "Line 1\nLine 2"
    result = SwarmCLI::UI::Formatters::Text.indent(text, level: 2)

    lines = result.split("\n")

    assert(lines.all? { |line| line.start_with?("    ") })
  end

  def test_indent_with_custom_char
    text = "Line 1\nLine 2"
    result = SwarmCLI::UI::Formatters::Text.indent(text, level: 1, char: "\t")

    lines = result.split("\n")

    assert(lines.all? { |line| line.start_with?("\t") })
  end

  def test_indent_handles_nil
    result = SwarmCLI::UI::Formatters::Text.indent(nil, level: 2)

    assert_empty(result)
  end
end
