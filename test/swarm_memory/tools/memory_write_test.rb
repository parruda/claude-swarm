# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class MemoryWriteToolTest < Minitest::Test
  def setup
    @storage = create_temp_storage
    @tool = SwarmMemory::Tools::MemoryWrite.new(storage: @storage, agent_name: :test_agent)
  end

  def teardown
    cleanup_storage(@storage)
  end

  def test_write_entry_with_minimal_metadata
    result = @tool.execute(
      file_path: "test/simple.md",
      content: "Simple content",
      title: "Simple Entry",
      type: "fact",
      confidence: "high",
      tags: ["test"],
      related: [],
      domain: "testing",
      source: "user",
    )

    assert_match(%r{Stored at memory://test/simple.md}, result)

    # Verify entry was written
    entry = @storage.read_entry(file_path: "test/simple.md")

    assert_equal("Simple content", entry.content)
    assert_equal("Simple Entry", entry.title)
  end

  def test_write_entry_with_full_metadata
    result = @tool.execute(
      file_path: "test/with_meta.md",
      content: "Content with metadata",
      title: "Entry With Metadata",
      type: "concept",
      confidence: "high",
      tags: ["test", "ruby"],
      related: [],
      domain: "programming/ruby",
      source: "documentation",
    )

    assert_match(%r{Stored at memory://test/with_meta.md}, result)

    # Verify metadata was stored
    entry = @storage.read_entry(file_path: "test/with_meta.md")

    assert_equal("concept", entry.metadata["type"])
    assert_equal("high", entry.metadata["confidence"])
    assert_equal(["test", "ruby"], entry.metadata["tags"])
  end

  def test_write_skill_with_tools_and_permissions
    # Write a skill with tools and permissions (ALL required parameters)
    result = @tool.execute(
      file_path: "skill/debug-react.md",
      content: "# Debug React Performance\n\n1. Profile components\n2. Check re-renders\n3. Optimize",
      title: "Debug React Performance",
      type: "skill",
      confidence: "high",
      tags: ["react", "performance", "debugging"],
      related: [],
      domain: "frontend/react",
      source: "experimentation",
      tools: ["Read", "Edit", "Bash", "Grep"],
      permissions: {
        "Bash" => { "allowed_commands" => ["^npm", "^git status"] },
        "Write" => { "denied_paths" => ["secrets/**"] },
      },
    )

    assert_match(%r{Stored at memory://skill/debug-react.md}, result)

    # Verify skill was stored with all metadata
    entry = @storage.read_entry(file_path: "skill/debug-react.md")

    assert_equal("skill", entry.metadata["type"])
    assert_equal(["Read", "Edit", "Bash", "Grep"], entry.metadata["tools"])
    assert_equal({ "Bash" => { "allowed_commands" => ["^npm", "^git status"] }, "Write" => { "denied_paths" => ["secrets/**"] } }, entry.metadata["permissions"])
    assert_match(/Debug React Performance/, entry.content)
  end

  def test_write_skill_with_empty_tools_list
    # Skill with no specific tools (will use agent's default tools)
    result = @tool.execute(
      file_path: "skill/simple-task.md",
      content: "# Simple Task\n\nJust use default tools",
      title: "Simple Task",
      type: "skill",
      confidence: "medium",
      tags: ["simple", "task"],
      related: [],
      domain: "utilities",
      source: "experimentation",
      tools: [],
      permissions: {},
    )

    assert_match(%r{Stored at memory://skill/simple-task.md}, result)

    entry = @storage.read_entry(file_path: "skill/simple-task.md")

    assert_equal("skill", entry.metadata["type"])
    assert_empty(entry.metadata["tools"])
  end

  def test_write_skill_without_tools_parameter
    # Skill without tools parameter (will use agent's current tools)
    result = @tool.execute(
      file_path: "skill/no-tools.md",
      content: "# No specific tools",
      title: "No Tools",
      type: "skill",
      confidence: "medium",
      tags: ["generic"],
      related: [],
      domain: "utilities",
      source: "experimentation",
    )

    assert_match(%r{Stored at memory://skill/no-tools.md}, result)

    entry = @storage.read_entry(file_path: "skill/no-tools.md")

    assert_equal("skill", entry.metadata["type"])
    assert_nil(entry.metadata["tools"])
  end

  def test_permissions_with_allowed_and_denied_paths
    @tool.execute(
      file_path: "skill/file-manager.md",
      content: "# File Management Skill",
      title: "File Manager",
      type: "skill",
      confidence: "high",
      tags: ["files", "management"],
      related: [],
      domain: "utilities",
      source: "experimentation",
      tools: ["Read", "Write", "Edit"],
      permissions: {
        "Write" => {
          "allowed_paths" => ["tmp/**/*", "workspace/**/*"],
          "denied_paths" => ["tmp/secrets/**"],
        },
        "Read" => {
          "allowed_paths" => ["**/*"],
        },
      },
    )

    entry = @storage.read_entry(file_path: "skill/file-manager.md")
    write_perms = entry.metadata["permissions"]["Write"]

    assert_equal(["tmp/**/*", "workspace/**/*"], write_perms["allowed_paths"])
    assert_equal(["tmp/secrets/**"], write_perms["denied_paths"])
  end
end
