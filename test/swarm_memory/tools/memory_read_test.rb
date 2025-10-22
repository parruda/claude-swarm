# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class MemoryReadToolTest < Minitest::Test
  def setup
    @storage = create_temp_storage
    @tool = SwarmMemory::Tools::MemoryRead.new(storage: @storage, agent_name: :test_agent)
  end

  def teardown
    cleanup_storage(@storage)
  end

  def test_returns_json_with_line_numbers_in_content
    # Write entry with minimal metadata
    @storage.write(
      file_path: "test/plain.md",
      content: "Line 1\nLine 2\nLine 3",
      title: "Plain Entry",
      metadata: { "type" => "fact" },
    )

    result = @tool.execute(file_path: "test/plain.md")

    # Should always return JSON with line numbers in content
    parsed = JSON.parse(result)

    assert_match(/     1→Line 1/, parsed["content"])
    assert_match(/     2→Line 2/, parsed["content"])
    assert_match(/     3→Line 3/, parsed["content"])
    assert_equal("Plain Entry", parsed["metadata"]["title"])
    assert_equal("fact", parsed["metadata"]["type"])
  end

  def test_returns_json_with_all_metadata
    # Write entry with full metadata
    @storage.write(
      file_path: "test/with_meta.md",
      content: "Content with metadata",
      title: "Entry With Metadata",
      metadata: {
        "type" => "concept",
        "confidence" => "high",
        "tags" => ["test", "ruby"],
      },
    )

    result = @tool.execute(file_path: "test/with_meta.md")

    # Should return JSON format with line numbers in content
    parsed = JSON.parse(result)

    assert_match(/     1→Content with metadata/, parsed["content"])
    assert_equal("Entry With Metadata", parsed["metadata"]["title"])
    assert_equal("concept", parsed["metadata"]["type"])
    assert_equal("high", parsed["metadata"]["confidence"])
    assert_equal(["test", "ruby"], parsed["metadata"]["tags"])
  end

  def test_returns_json_for_skill_with_tools_and_permissions
    # Write skill entry with tools and permissions
    @storage.write(
      file_path: "skill/debug-react.md",
      content: "# Debug React Performance\n\n1. Profile components\n2. Check re-renders",
      title: "Debug React Performance",
      metadata: {
        "type" => "skill",
        "confidence" => "high",
        "tags" => ["react", "performance"],
        "tools" => ["Read", "Edit", "Bash"],
        "permissions" => {
          "Bash" => { "allowed_commands" => ["^npm", "^git"] },
        },
      },
    )

    result = @tool.execute(file_path: "skill/debug-react.md")

    # Should return JSON with all skill metadata and line numbers in content
    parsed = JSON.parse(result)

    assert_equal("Debug React Performance", parsed["metadata"]["title"])
    assert_equal("skill", parsed["metadata"]["type"])
    assert_equal(["Read", "Edit", "Bash"], parsed["metadata"]["tools"])
    assert_equal({ "Bash" => { "allowed_commands" => ["^npm", "^git"] } }, parsed["metadata"]["permissions"])

    # Content should have line numbers
    assert_match(/     1→# Debug React Performance/, parsed["content"])
    assert_match(/     3→1\. Profile components/, parsed["content"])
    assert_match(/     4→2\. Check re-renders/, parsed["content"])
  end

  def test_error_for_nonexistent_file
    result = @tool.execute(file_path: "nonexistent.md")

    assert_match(/InputValidationError/, result)
    assert_match(/not found/, result)
  end
end
