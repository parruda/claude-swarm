# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class McpToolsOptionsTest < Minitest::Test
  def test_parse_no_tools_returns_empty_array
    options = SwarmCLI::McpToolsOptions.new
    options.parse([])

    assert_empty(options.tool_names)
  end

  def test_parse_single_tool_name
    options = SwarmCLI::McpToolsOptions.new
    options.parse(["Read"])

    assert_equal(["Read"], options.tool_names)
  end

  def test_parse_multiple_tool_names_space_separated
    options = SwarmCLI::McpToolsOptions.new
    options.parse(["Read", "Write", "Bash"])

    assert_equal(["Read", "Write", "Bash"], options.tool_names)
  end

  def test_parse_multiple_tool_names_comma_separated
    options = SwarmCLI::McpToolsOptions.new
    options.parse(["Read,Write,Bash"])

    assert_equal(["Read", "Write", "Bash"], options.tool_names)
  end

  def test_parse_mixed_comma_and_space_separated
    options = SwarmCLI::McpToolsOptions.new
    options.parse(["Read,Write", "Bash"])

    assert_equal(["Read", "Write", "Bash"], options.tool_names)
  end

  def test_parse_strips_whitespace
    options = SwarmCLI::McpToolsOptions.new
    options.parse(["  Read  ,  Write  "])

    assert_equal(["Read", "Write"], options.tool_names)
  end

  def test_validate_success_with_valid_tool_names
    options = SwarmCLI::McpToolsOptions.new
    options.parse(["Read", "Write", "Edit"])

    # Should not raise
    options.validate!
  end

  def test_validate_success_with_no_tools
    options = SwarmCLI::McpToolsOptions.new
    options.parse([])

    # Should not raise (defaults to all tools)
    options.validate!
  end

  def test_validate_fails_with_invalid_tool_names
    options = SwarmCLI::McpToolsOptions.new
    options.parse(["Read", "InvalidTool", "AnotherInvalidTool"])

    error = assert_raises(SwarmCLI::ExecutionError) do
      options.validate!
    end

    assert_match(/Invalid tool names/, error.message)
    assert_match(/InvalidTool/, error.message)
    assert_match(/AnotherInvalidTool/, error.message)
    assert_match(/Available:/, error.message)
  end

  def test_validate_fails_with_single_invalid_tool
    options = SwarmCLI::McpToolsOptions.new
    options.parse(["InvalidTool"])

    error = assert_raises(SwarmCLI::ExecutionError) do
      options.validate!
    end

    assert_match(/Invalid tool names/, error.message)
    assert_match(/InvalidTool/, error.message)
  end

  def test_tool_names_handles_string_input
    options = SwarmCLI::McpToolsOptions.new
    # Simulate what TTY::Option might return
    options.params[:tool_names] = "Read,Write"

    assert_equal(["Read", "Write"], options.tool_names)
  end

  def test_tool_names_handles_array_input
    options = SwarmCLI::McpToolsOptions.new
    # Simulate what TTY::Option might return
    options.params[:tool_names] = ["Read", "Write"]

    assert_equal(["Read", "Write"], options.tool_names)
  end

  def test_tool_names_returns_empty_for_nil
    options = SwarmCLI::McpToolsOptions.new
    options.params[:tool_names] = nil

    assert_empty(options.tool_names)
  end
end
