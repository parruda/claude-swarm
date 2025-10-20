# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class MemoryDefragToolTest < Minitest::Test
  def setup
    @storage = create_temp_storage
    @tool = SwarmMemory::Tools::MemoryDefrag.new(storage: @storage)
  end

  def teardown
    cleanup_storage(@storage)
  end

  def test_analyze_action
    # Create test entries
    @storage.write(
      file_path: "test/entry1",
      content: create_sample_entry(type: "concept", confidence: "high"),
      title: "Entry 1",
    )

    result = @tool.execute(action: "analyze")

    assert_match(/Memory Health Report/, result)
    assert_match(/Total entries: 1/, result)
    assert_match(/Health Score:/, result)
  end

  def test_find_duplicates_action
    # Create similar entries
    content1 = "Ruby is a programming language with elegant syntax"
    content2 = "Ruby is a programming language with dynamic typing"

    @storage.write(file_path: "entry1", content: content1, title: "Entry 1")
    @storage.write(file_path: "entry2", content: content2, title: "Entry 2")

    result = @tool.execute(action: "find_duplicates", similarity_threshold: 0.5)

    assert_match(/Potential Duplicates/, result)
  end

  def test_find_low_quality_action
    # Create entry without frontmatter
    @storage.write(file_path: "no_meta", content: "plain content", title: "No Meta")

    result = @tool.execute(action: "find_low_quality")

    assert_match(/Low-Quality Entries/, result)
    assert_match(/no_meta/, result)
  end

  def test_find_archival_candidates_action
    @storage.write(file_path: "test/entry", content: "test", title: "Test")

    result = @tool.execute(action: "find_archival_candidates", age_days: 0)

    assert_match(/Archival Candidates/, result)
  end

  def test_full_action
    @storage.write(file_path: "test/entry", content: create_sample_entry, title: "Test")

    result = @tool.execute(action: "full")

    assert_match(/Full Memory Defrag Analysis/, result)
    assert_match(/Memory Health Report/, result)
    # Report includes all sections (even if no matches found)
    assert_match(/duplicate/i, result)
    assert_match(/Low-Quality/, result)
    assert_match(/older than|Archival Candidates/i, result)
  end

  def test_invalid_action
    result = @tool.execute(action: "invalid_action")

    assert_match(/tool_use_error/, result)
    assert_match(/Invalid action/, result)
  end

  def test_default_action_is_analyze
    @storage.write(file_path: "test", content: "test", title: "Test")

    result = @tool.execute

    assert_match(/Memory Health Report/, result)
  end
end
