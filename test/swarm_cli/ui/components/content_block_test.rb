# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class ContentBlockTest < Minitest::Test
  def setup
    @pastel = Pastel.new(enabled: false)
    @block = SwarmCLI::UI::Components::ContentBlock.new(pastel: @pastel)
  end

  def test_render_hash_with_simple_values
    data = { key1: "value1", key2: "value2" }
    result = @block.render_hash(data, indent: 0)

    assert_includes(result, "key1:")
    assert_includes(result, "value1")
    assert_includes(result, "key2:")
    assert_includes(result, "value2")
  end

  def test_render_hash_with_label
    data = { key: "value" }
    result = @block.render_hash(data, indent: 0, label: "Arguments")

    assert_includes(result, "Arguments:")
    assert_includes(result, "key:")
  end

  def test_render_hash_returns_empty_for_nil
    result = @block.render_hash(nil, indent: 0)

    assert_empty(result)
  end

  def test_render_hash_returns_empty_for_empty_hash
    result = @block.render_hash({}, indent: 0)

    assert_empty(result)
  end

  def test_render_hash_with_indentation
    data = { key: "value" }
    result = @block.render_hash(data, indent: 2)

    # Should have indentation
    assert_match(/^    /, result.split("\n").first)
  end

  def test_render_hash_with_array_value
    data = { tools: ["Read", "Write", "Edit"] }
    result = @block.render_hash(data, indent: 0)

    assert_includes(result, "tools:")
    assert_includes(result, "Read, Write, Edit")
  end

  def test_render_hash_with_hash_value
    data = { config: { enabled: true, timeout: 30 } }
    result = @block.render_hash(data, indent: 0)

    assert_includes(result, "config:")
    assert_includes(result, "enabled: true")
  end

  def test_render_hash_with_numeric_value
    data = { count: 42, ratio: 3.14 }
    result = @block.render_hash(data, indent: 0)

    assert_includes(result, "count:")
    assert_includes(result, "42")
    assert_includes(result, "ratio:")
    assert_includes(result, "3.14")
  end

  def test_render_hash_with_boolean_values
    data = { enabled: true, disabled: false }
    result = @block.render_hash(data, indent: 0)

    assert_includes(result, "enabled:")
    assert_includes(result, "true")
    assert_includes(result, "disabled:")
    assert_includes(result, "false")
  end

  def test_render_text_simple
    result = @block.render_text("Hello World", indent: 0)

    assert_includes(result, "Hello World")
  end

  def test_render_text_multiline
    text = "Line 1\nLine 2\nLine 3"
    result = @block.render_text(text, indent: 0)

    assert_includes(result, "Line 1")
    assert_includes(result, "Line 2")
    assert_includes(result, "Line 3")
  end

  def test_render_text_returns_empty_for_nil
    result = @block.render_text(nil, indent: 0)

    assert_empty(result)
  end

  def test_render_text_returns_empty_for_empty_string
    result = @block.render_text("", indent: 0)

    assert_empty(result)
  end

  def test_render_text_with_truncation
    text = (1..20).map { |i| "Line #{i}" }.join("\n")
    result = @block.render_text(text, indent: 0, truncate: true, max_lines: 5)

    lines = result.split("\n")
    # Should truncate to 5 lines plus truncation message
    assert_operator(lines.size, :<=, 7) # 5 content + maybe label + truncation message
  end

  def test_render_list_with_items
    items = ["Item 1", "Item 2", "Item 3"]
    result = @block.render_list(items, indent: 0)

    assert_includes(result, "Item 1")
    assert_includes(result, "Item 2")
    assert_includes(result, "Item 3")
    assert_includes(result, SwarmCLI::UI::Icons::BULLET)
  end

  def test_render_list_returns_empty_for_nil
    result = @block.render_list(nil, indent: 0)

    assert_empty(result)
  end

  def test_render_list_returns_empty_for_empty_array
    result = @block.render_list([], indent: 0)

    assert_empty(result)
  end

  def test_render_list_with_custom_bullet
    items = ["Item 1"]
    result = @block.render_list(items, indent: 0, bullet: "-")

    assert_includes(result, "- Item 1")
  end
end
