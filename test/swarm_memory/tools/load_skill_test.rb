# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

# Mock classes for testing LoadSkill without full SwarmSDK setup
class MockChat
  attr_reader :tools, :immutable_tool_names, :active_skill_path

  def initialize
    @tools = []
    @immutable_tool_names = Set.new(["Think", "Clock", "TodoWrite"])
    @active_skill_path = nil
  end

  def mark_tools_immutable(*tool_names)
    @immutable_tool_names.merge(tool_names.flatten.map(&:to_s))
  end

  def remove_mutable_tools
    @tools.select! { |tool| @immutable_tool_names.include?(tool.name) }
  end

  def add_tool(tool)
    @tools << tool
  end
  alias_method :with_tool, :add_tool

  def mark_skill_loaded(file_path)
    @active_skill_path = file_path
  end

  def skill_loaded?
    !@active_skill_path.nil?
  end
end

class MockTool
  attr_reader :name

  def initialize(name)
    @name = name
  end
end

class MockToolConfigurator
  def create_tool_instance(tool_name, agent_name, directory)
    MockTool.new(tool_name.to_s)
  end

  def wrap_tool_with_permissions(tool_instance, permissions, agent_definition)
    tool_instance
  end
end

class MockAgentDefinition
  attr_reader :bypass_permissions, :directory

  def initialize(bypass: false, directory: "/test")
    @bypass_permissions = bypass
    @directory = directory
  end
end

class LoadSkillToolTest < Minitest::Test
  def setup
    @storage = create_temp_storage
    @chat = MockChat.new
    @tool_configurator = MockToolConfigurator.new
    @agent_definition = MockAgentDefinition.new

    # Create LoadSkill tool
    @tool = SwarmMemory::Tools::LoadSkill.new(
      storage: @storage,
      agent_name: :test_agent,
      chat: @chat,
      tool_configurator: @tool_configurator,
      agent_definition: @agent_definition,
    )
  end

  def teardown
    cleanup_storage(@storage)
  end

  def test_marks_memory_tools_as_immutable
    # Verify immutable tools were marked during initialization
    expected_immutable = [
      "Think",
      "Clock",
      "TodoWrite",
      "MemoryWrite",
      "MemoryRead",
      "MemoryEdit",
      "MemoryMultiEdit",
      "MemoryDelete",
      "MemoryGlob",
      "MemoryGrep",
      "MemoryDefrag",
      "LoadSkill",
    ]

    assert_equal(expected_immutable.sort, @chat.immutable_tool_names.to_a.sort)
  end

  def test_fail_if_not_in_skills_hierarchy
    # Create a non-skill entry
    @storage.write(
      file_path: "test/not-skill.md",
      content: "Regular entry",
      title: "Not a Skill",
      metadata: { "type" => "concept" },
    )

    result = @tool.execute(file_path: "test/not-skill.md")

    assert_match(/InputValidationError/, result)
    assert_match(%r{Skills must be stored in skill/ hierarchy}, result)
  end

  def test_fail_if_not_skill_type
    # Create entry in skill/ but wrong type
    @storage.write(
      file_path: "skill/not-skill.md",
      content: "Not actually a skill",
      title: "Not a Skill",
      metadata: { "type" => "concept" },
    )

    result = @tool.execute(file_path: "skill/not-skill.md")

    assert_match(/InputValidationError/, result)
    assert_match(/is not a skill/, result)
  end

  def test_fail_for_nonexistent_skill
    result = @tool.execute(file_path: "skill/nonexistent.md")

    assert_match(/InputValidationError/, result)
    assert_match(/not found/, result)
  end

  def test_load_skill_with_tools
    # Create a valid skill
    @storage.write(
      file_path: "skill/debug-react.md",
      content: "# Debug React\n\n1. Profile\n2. Optimize",
      title: "Debug React Performance",
      metadata: {
        "type" => "skill",
        "tools" => ["Read", "Edit", "Bash"],
      },
    )

    # Add some initial mutable tools to chat
    @chat.add_tool(MockTool.new("Write"))
    @chat.add_tool(MockTool.new("Grep"))
    @chat.add_tool(MockTool.new("Think")) # Immutable
    @chat.add_tool(MockTool.new("Clock")) # Immutable
    @chat.add_tool(MockTool.new("TodoWrite")) # Immutable

    assert_equal(5, @chat.tools.size)

    result = @tool.execute(file_path: "skill/debug-react.md")

    # Should succeed
    assert_match(/Loaded skill: Debug React Performance/, result)
    assert_match(/Profile/, result)
    assert_match(/Optimize/, result)

    # Verify mutable tools were replaced
    tool_names = @chat.tools.map(&:name)

    assert_includes(tool_names, "Read")
    assert_includes(tool_names, "Edit")
    assert_includes(tool_names, "Bash")
    assert_includes(tool_names, "Think") # Immutable preserved
    assert_includes(tool_names, "Clock") # Immutable preserved
    assert_includes(tool_names, "TodoWrite") # Immutable preserved

    # Mutable tools should be removed
    refute_includes(tool_names, "Write")
    refute_includes(tool_names, "Grep")

    # Skill should be marked as loaded
    assert_predicate(@chat, :skill_loaded?)
    assert_equal("skill/debug-react.md", @chat.active_skill_path)
  end

  def test_load_skill_without_tools_keeps_current_tools
    # Create skill without tools specified (nil)
    @storage.write(
      file_path: "skill/simple.md",
      content: "# Simple Task",
      title: "Simple Task",
      metadata: { "type" => "skill" },
    )

    # Add initial tools
    @chat.add_tool(MockTool.new("Write"))
    @chat.add_tool(MockTool.new("Read"))
    @chat.add_tool(MockTool.new("Think"))
    @chat.add_tool(MockTool.new("Clock"))
    @chat.add_tool(MockTool.new("TodoWrite"))

    initial_tools_count = @chat.tools.size

    result = @tool.execute(file_path: "skill/simple.md")

    # Should succeed
    assert_match(/Loaded skill: Simple Task/, result)

    # Since no tools specified, should keep ALL current tools (no swap)
    tool_names = @chat.tools.map(&:name)

    # All tools should still be present (both mutable and immutable)
    assert_includes(tool_names, "Write") # Mutable kept
    assert_includes(tool_names, "Read") # Mutable kept
    assert_includes(tool_names, "Think") # Immutable kept
    assert_includes(tool_names, "Clock") # Immutable kept
    assert_includes(tool_names, "TodoWrite") # Immutable kept

    # Tool count should be unchanged
    assert_equal(initial_tools_count, @chat.tools.size)
  end

  def test_load_skill_preserves_immutable_tools
    # Create skill
    @storage.write(
      file_path: "skill/test.md",
      content: "# Test Skill",
      title: "Test",
      metadata: {
        "type" => "skill",
        "tools" => ["Read"],
      },
    )

    # Add memory tools (should be immutable)
    @chat.add_tool(MockTool.new("MemoryRead"))
    @chat.add_tool(MockTool.new("MemoryWrite"))
    @chat.add_tool(MockTool.new("LoadSkill"))
    @chat.add_tool(MockTool.new("Think"))
    @chat.add_tool(MockTool.new("Clock"))
    @chat.add_tool(MockTool.new("TodoWrite"))
    @chat.add_tool(MockTool.new("Write")) # Mutable

    result = @tool.execute(file_path: "skill/test.md")

    assert_match(/Loaded skill: Test/, result)

    # All immutable tools should be preserved
    tool_names = @chat.tools.map(&:name)

    assert_includes(tool_names, "MemoryRead")
    assert_includes(tool_names, "MemoryWrite")
    assert_includes(tool_names, "LoadSkill")
    assert_includes(tool_names, "Think")
    assert_includes(tool_names, "Clock")
    assert_includes(tool_names, "TodoWrite")
    assert_includes(tool_names, "Read") # Added by skill

    # Mutable tool should be removed
    refute_includes(tool_names, "Write")
  end

  def test_load_multiple_skills_replaces_tools
    # Create two skills
    @storage.write(
      file_path: "skill/skill1.md",
      content: "# Skill 1",
      title: "Skill 1",
      metadata: {
        "type" => "skill",
        "tools" => ["Read", "Edit"],
      },
    )

    @storage.write(
      file_path: "skill/skill2.md",
      content: "# Skill 2",
      title: "Skill 2",
      metadata: {
        "type" => "skill",
        "tools" => ["Write", "Bash"],
      },
    )

    # Add immutable tools
    @chat.add_tool(MockTool.new("Think"))
    @chat.add_tool(MockTool.new("Clock"))
    @chat.add_tool(MockTool.new("TodoWrite"))

    # Load first skill
    @tool.execute(file_path: "skill/skill1.md")
    tools_after_first = @chat.tools.map(&:name)

    assert_includes(tools_after_first, "Read")
    assert_includes(tools_after_first, "Edit")
    assert_equal("skill/skill1.md", @chat.active_skill_path)

    # Load second skill (should replace first skill's tools)
    @tool.execute(file_path: "skill/skill2.md")
    tools_after_second = @chat.tools.map(&:name)

    assert_includes(tools_after_second, "Write")
    assert_includes(tools_after_second, "Bash")
    assert_includes(tools_after_second, "Think") # Immutable preserved
    assert_includes(tools_after_second, "Clock") # Immutable preserved
    assert_includes(tools_after_second, "TodoWrite") # Immutable preserved

    # First skill's tools should be gone
    refute_includes(tools_after_second, "Read")
    refute_includes(tools_after_second, "Edit")
    assert_equal("skill/skill2.md", @chat.active_skill_path)
  end

  def test_returns_content_with_line_numbers
    @storage.write(
      file_path: "skill/test.md",
      content: "Line 1\nLine 2\nLine 3",
      title: "Test",
      metadata: { "type" => "skill", "tools" => [] },
    )

    result = @tool.execute(file_path: "skill/test.md")

    # Should include line numbers
    assert_match(/     1→Line 1/, result)
    assert_match(/     2→Line 2/, result)
    assert_match(/     3→Line 3/, result)
  end
end
