# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Tools
    class MemoryToolsTest < Minitest::Test
      def setup
        @memory = Tools::Stores::MemoryStorage.new(persist_to: Dir.mktmpdir + "/memory-test.json")
        @agent_name = :test_agent
        @write_tool = Memory::MemoryWrite.create_for_memory(@memory)
        @read_tool = Memory::MemoryRead.create_for_memory(@memory, @agent_name)
        @delete_tool = Memory::MemoryDelete.create_for_memory(@memory)
        @glob_tool = Memory::MemoryGlob.create_for_memory(@memory)
        @grep_tool = Memory::MemoryGrep.create_for_memory(@memory)
        @edit_tool = Memory::MemoryEdit.create_for_memory(@memory, @agent_name)
        @multi_edit_tool = Memory::MemoryMultiEdit.create_for_memory(@memory, @agent_name)

        # Clear read tracker before each test
        Tools::Stores::StorageReadTracker.clear(@agent_name)
      end

      # ScratchpadWrite tests

      def test_memory_write_stores_content
        result = @write_tool.execute(
          file_path: "test/path",
          content: "Test content",
          title: "Test title",
        )

        assert_match(%r{Stored at memory://test/path}, result)
        assert_match(/\(12B\)/, result) # "Test content" is 12 bytes
      end

      def test_memory_write_returns_formatted_size
        # Test bytes
        result = @write_tool.execute(file_path: "a", content: "x" * 500, title: "Test")

        assert_match(/\(500B\)/, result)

        # Test KB
        result = @write_tool.execute(file_path: "b", content: "x" * 5000, title: "Test")

        assert_match(/\(5.0KB\)/, result)

        # Test KB (large)
        result = @write_tool.execute(file_path: "c", content: "x" * 500_000, title: "Test")

        assert_match(/\(500.0KB\)/, result)

        # Test MB
        result = @write_tool.execute(file_path: "d", content: "x" * 1_000_000, title: "Test")

        assert_match(/\(1.0MB\)/, result)
      end

      def test_memory_write_handles_errors
        # Missing file_path
        result = @write_tool.execute(file_path: "", content: "test", title: "Test")

        assert_match(/Error: file_path is required/, result)

        # Missing content
        result = @write_tool.execute(file_path: "test", content: nil, title: "Test")

        assert_match(/Error: content is required/, result)

        # Missing title
        result = @write_tool.execute(file_path: "test", content: "test", title: "")

        assert_match(/Error: title is required/, result)
      end

      def test_memory_write_handles_size_limit_error
        large_content = "x" * (Tools::Stores::Storage::MAX_ENTRY_SIZE + 1)

        result = @write_tool.execute(file_path: "test", content: large_content, title: "Too big")

        assert_match(/Error:/, result)
        assert_match(/exceeds maximum size/, result)
      end

      # ScratchpadRead tests

      def test_memory_read_returns_content_with_line_numbers
        @memory.write(file_path: "test/path", content: "Line 1\nLine 2\nLine 3", title: "Test")

        result = @read_tool.execute(file_path: "test/path")

        assert_match(/^\s*1→Line 1$/, result)
        assert_match(/^\s*2→Line 2$/, result)
        assert_match(/^\s*3→Line 3$/, result)
      end

      def test_memory_read_handles_missing_path
        result = @read_tool.execute(file_path: "nonexistent")

        assert_match(/Error:/, result)
        assert_match(%r{memory://nonexistent not found}, result)
      end

      def test_memory_read_handles_empty_path
        result = @read_tool.execute(file_path: "")

        assert_match(/Error:/, result)
        assert_match(/file_path is required/, result)
      end

      # Integration tests

      def test_memory_tools_share_same_storage
        # Write using write tool
        @write_tool.execute(file_path: "shared", content: "Shared content", title: "Shared")

        # Read using read tool (returns content with line numbers)
        result = @read_tool.execute(file_path: "shared")

        assert_match(/^\s*1→Shared content$/, result)

        # Glob using glob tool
        glob_result = @glob_tool.execute(pattern: "shared")

        assert_match(%r{memory://shared - "Shared"}, glob_result)
      end

      def test_memory_tools_work_with_complex_paths
        paths = [
          "parallel/batch_a3f5e9c2/task_0",
          "analysis/performance/report",
          "research/frameworks/rails/patterns",
        ]

        paths.each_with_index do |path, i|
          @write_tool.execute(file_path: path, content: "Content #{i}", title: "Title #{i}")
        end

        result = @glob_tool.execute(pattern: "**")

        paths.each do |path|
          assert_match(%r{memory://#{Regexp.escape(path)}}, result)
        end
      end

      def test_memory_tools_handle_unicode_content
        unicode_content = "Hello 🌍! Привет мир! 你好世界!"

        @write_tool.execute(file_path: "unicode", content: unicode_content, title: "Unicode test")

        result = @read_tool.execute(file_path: "unicode")

        # Read now returns content with line numbers
        assert_match(/^\s*1→#{Regexp.escape(unicode_content)}$/, result)
      end

      def test_multiple_tool_instances_share_same_memory
        # Create another set of tools for the same memory storage
        write_tool2 = Memory::MemoryWrite.create_for_memory(@memory)
        read_tool2 = Memory::MemoryRead.create_for_memory(@memory, @agent_name)

        # Write with first tool
        @write_tool.execute(file_path: "test", content: "Original", title: "Test")

        # Read with second tool (returns content with line numbers)
        result = read_tool2.execute(file_path: "test")

        assert_match(/^\s*1→Original$/, result)

        # Update with second tool
        write_tool2.execute(file_path: "test", content: "Updated", title: "Updated")

        # Read with first tool (returns content with line numbers)
        result = @read_tool.execute(file_path: "test")

        assert_match(/^\s*1→Updated$/, result)
      end

      def test_memory_write_with_nil_file_path
        result = @write_tool.execute(file_path: nil, content: "test", title: "Test")

        assert_includes(result, "Error: file_path is required")
      end

      def test_memory_write_with_blank_file_path
        result = @write_tool.execute(file_path: "   ", content: "test", title: "Test")

        assert_includes(result, "Error: file_path is required")
      end

      def test_memory_write_with_empty_file_path
        result = @write_tool.execute(file_path: "", content: "test", title: "Test")

        assert_includes(result, "Error: file_path is required")
      end

      def test_memory_read_with_nil_file_path
        result = @read_tool.execute(file_path: nil)

        assert_includes(result, "Error: file_path is required")
      end

      def test_memory_read_with_blank_file_path
        result = @read_tool.execute(file_path: "   ")

        assert_includes(result, "Error: file_path is required")
      end

      def test_memory_read_with_empty_file_path
        result = @read_tool.execute(file_path: "")

        assert_includes(result, "Error: file_path is required")
      end

      # ScratchpadDelete tests

      def test_memory_delete_removes_entry
        @memory.write(file_path: "test/path", content: "Test content", title: "Test")

        result = @delete_tool.execute(file_path: "test/path")

        assert_equal("Deleted memory://test/path", result)

        # Verify entry is deleted
        read_result = @read_tool.execute(file_path: "test/path")

        assert_includes(read_result, "Error")
        assert_includes(read_result, "not found")
      end

      def test_memory_delete_updates_total_size
        @memory.write(file_path: "test/path", content: "x" * 1000, title: "Test")
        initial_size = @memory.total_size

        assert_equal(1000, initial_size)

        @delete_tool.execute(file_path: "test/path")

        assert_equal(0, @memory.total_size)
      end

      def test_memory_delete_nonexistent_path
        result = @delete_tool.execute(file_path: "nonexistent/path")

        assert_includes(result, "Error")
        assert_includes(result, "not found")
      end

      def test_memory_delete_empty_file_path
        result = @delete_tool.execute(file_path: "")

        assert_includes(result, "Error")
        assert_includes(result, "file_path is required")
      end

      def test_memory_delete_frees_space_for_new_writes
        # Fill up some space
        @memory.write(file_path: "test/old", content: "x" * 500_000, title: "Old")
        @memory.write(file_path: "test/keep", content: "y" * 400_000, title: "Keep")

        assert_equal(900_000, @memory.total_size)

        # Delete the old entry
        @delete_tool.execute(file_path: "test/old")

        assert_equal(400_000, @memory.total_size)

        # Verify we can write new content
        result = @write_tool.execute(file_path: "test/new", content: "z" * 300_000, title: "New")

        assert_includes(result, "Stored")
        assert_equal(700_000, @memory.total_size)
      end

      # ScratchpadGlob tests

      def test_memory_glob_returns_matching_entries
        @memory.write(file_path: "parallel/batch1/task_0", content: "T0", title: "Task 0")
        @memory.write(file_path: "parallel/batch1/task_1", content: "T1", title: "Task 1")
        @memory.write(file_path: "parallel/batch2/task_0", content: "T2", title: "Task 2")
        @memory.write(file_path: "analysis/report", content: "R", title: "Report")

        result = @glob_tool.execute(pattern: "parallel/*/task_0")

        assert_match(%r{Memory entries matching 'parallel/\*/task_0' \(2 entries\):}, result)
        assert_match(%r{memory://parallel/batch1/task_0 - "Task 0"}, result)
        assert_match(%r{memory://parallel/batch2/task_0 - "Task 2"}, result)
        refute_match(/analysis/, result)
      end

      def test_memory_glob_with_recursive_pattern
        @memory.write(file_path: "parallel/batch1/task_0", content: "T0", title: "Task 0")
        @memory.write(file_path: "parallel/batch1/sub/task_1", content: "T1", title: "Task 1")
        @memory.write(file_path: "analysis/report", content: "R", title: "Report")

        result = @glob_tool.execute(pattern: "parallel/**")

        assert_match(%r{Memory entries matching 'parallel/\*\*' \(2 entries\):}, result)
        assert_match(%r{memory://parallel/batch1/task_0}, result)
        assert_match(%r{memory://parallel/batch1/sub/task_1}, result)
      end

      def test_memory_glob_no_matches
        @memory.write(file_path: "a/1", content: "A1", title: "Entry A1")

        result = @glob_tool.execute(pattern: "b/*")

        assert_equal("No entries found matching pattern 'b/*'", result)
      end

      def test_memory_glob_shows_sizes
        @memory.write(file_path: "test/small", content: "x" * 100, title: "Small")
        @memory.write(file_path: "test/large", content: "x" * 50_000, title: "Large")

        result = @glob_tool.execute(pattern: "test/*")

        assert_match(%r{memory://test/small.*\(100B\)}, result)
        assert_match(%r{memory://test/large.*\(50.0KB\)}, result)
      end

      def test_memory_glob_handles_errors
        result = @glob_tool.execute(pattern: "")

        assert_match(/Error: pattern is required/, result)
      end

      # ScratchpadGrep tests

      def test_memory_grep_files_with_matches
        @memory.write(file_path: "a", content: "Hello world", title: "A")
        @memory.write(file_path: "b", content: "Goodbye world", title: "B")
        @memory.write(file_path: "c", content: "Nothing here", title: "C")

        result = @grep_tool.execute(pattern: "world")

        assert_match(/Memory entries matching 'world' \(2 entries\):/, result)
        assert_match(%r{memory://a}, result)
        assert_match(%r{memory://b}, result)
        refute_match(%r{memory://c}, result)
      end

      def test_memory_grep_case_insensitive
        @memory.write(file_path: "a", content: "Hello World", title: "A")
        @memory.write(file_path: "b", content: "hello world", title: "B")

        # Case sensitive (default)
        result = @grep_tool.execute(pattern: "hello")

        assert_match(/Memory entries matching 'hello' \(1 entry\):/, result)
        assert_match(%r{memory://b}, result)
        refute_match(%r{memory://a}, result)

        # Case insensitive
        result = @grep_tool.execute(pattern: "hello", case_insensitive: true)

        assert_match(/Memory entries matching 'hello' \(2 entries\):/, result)
        assert_match(%r{memory://a}, result)
        assert_match(%r{memory://b}, result)
      end

      def test_memory_grep_content_mode
        @memory.write(file_path: "test", content: "Line 1: error\nLine 2: ok\nLine 3: error", title: "Test")

        result = @grep_tool.execute(pattern: "error", output_mode: "content")

        assert_match(/Memory entries matching 'error' \(1 entry, 2 matches\):/, result)
        assert_match(%r{memory://test:}, result)
        assert_match(/1: Line 1: error/, result)
        assert_match(/3: Line 3: error/, result)
      end

      def test_memory_grep_count_mode
        @memory.write(file_path: "a", content: "foo bar foo", title: "A")
        @memory.write(file_path: "b", content: "foo", title: "B")

        result = @grep_tool.execute(pattern: "foo", output_mode: "count")

        assert_match(/Memory entries matching 'foo' \(2 entries, 3 total matches\):/, result)
        assert_match(%r{memory://a: 2 matches}, result)
        assert_match(%r{memory://b: 1 match}, result)
      end

      def test_memory_grep_no_matches
        @memory.write(file_path: "test", content: "hello", title: "Test")

        result = @grep_tool.execute(pattern: "goodbye")

        assert_equal("No matches found for pattern 'goodbye'", result)
      end

      def test_memory_grep_handles_errors
        result = @grep_tool.execute(pattern: "")

        assert_match(/Error: pattern is required/, result)
      end

      def test_memory_grep_invalid_regex
        @memory.write(file_path: "test", content: "test", title: "Test")

        result = @grep_tool.execute(pattern: "[invalid")

        assert_match(/Error: Invalid regex pattern/, result)
      end

      def test_memory_grep_invalid_output_mode
        @memory.write(file_path: "test", content: "test", title: "Test")

        result = @grep_tool.execute(pattern: "test", output_mode: "invalid")

        assert_match(/Error: Invalid output_mode/, result)
      end

      # ScratchpadEdit tests

      def test_memory_edit_replaces_content
        @memory.write(file_path: "test", content: "Hello world\nFoo bar", title: "Test")
        @read_tool.execute(file_path: "test") # Read before edit

        result = @edit_tool.execute(
          file_path: "test",
          old_string: "world",
          new_string: "universe",
        )

        assert_match(/Successfully replaced 1 occurrence/, result)

        updated_content = @memory.read(file_path: "test")

        assert_equal("Hello universe\nFoo bar", updated_content)
      end

      def test_memory_edit_with_replace_all
        @memory.write(file_path: "test", content: "foo bar foo baz foo", title: "Test")
        @read_tool.execute(file_path: "test")

        result = @edit_tool.execute(
          file_path: "test",
          old_string: "foo",
          new_string: "FOO",
          replace_all: true,
        )

        assert_match(/Successfully replaced 3 occurrence/, result)

        updated_content = @memory.read(file_path: "test")

        assert_equal("FOO bar FOO baz FOO", updated_content)
      end

      def test_memory_edit_requires_read_before_edit
        @memory.write(file_path: "test", content: "Hello world", title: "Test")

        result = @edit_tool.execute(
          file_path: "test",
          old_string: "world",
          new_string: "universe",
        )

        assert_match(/Error:.*Cannot edit memory entry without reading it first/, result)
      end

      def test_memory_edit_handles_missing_old_string
        @memory.write(file_path: "test", content: "Hello world", title: "Test")
        @read_tool.execute(file_path: "test")

        result = @edit_tool.execute(
          file_path: "test",
          old_string: "missing",
          new_string: "replacement",
        )

        assert_match(/Error:.*old_string not found/, result)
      end

      def test_memory_edit_handles_multiple_occurrences_without_replace_all
        @memory.write(file_path: "test", content: "foo bar foo", title: "Test")
        @read_tool.execute(file_path: "test")

        result = @edit_tool.execute(
          file_path: "test",
          old_string: "foo",
          new_string: "FOO",
        )

        assert_match(/Error:.*Found 2 occurrences/, result)
      end

      def test_memory_edit_preserves_title
        @memory.write(file_path: "test", content: "Original content", title: "Important Title")
        @read_tool.execute(file_path: "test")

        @edit_tool.execute(
          file_path: "test",
          old_string: "Original",
          new_string: "Updated",
        )

        entries = @memory.list
        entry = entries.find { |e| e[:path] == "test" }

        assert_equal("Important Title", entry[:title])
      end

      def test_memory_edit_validates_inputs
        # Empty file_path
        result = @edit_tool.execute(file_path: "", old_string: "foo", new_string: "bar")

        assert_match(/Error:.*file_path is required/, result)

        # Empty old_string
        @read_tool.execute(file_path: "test")
        result = @edit_tool.execute(file_path: "test", old_string: "", new_string: "bar")

        assert_match(/Error:.*old_string is required/, result)

        # Nil new_string
        result = @edit_tool.execute(file_path: "test", old_string: "foo", new_string: nil)

        assert_match(/Error:.*new_string is required/, result)

        # Same old_string and new_string
        @read_tool.execute(file_path: "test")
        result = @edit_tool.execute(file_path: "test", old_string: "foo", new_string: "foo")

        assert_match(/Error:.*must be different/, result)
      end

      def test_memory_edit_handles_missing_entry
        result = @edit_tool.execute(
          file_path: "nonexistent",
          old_string: "foo",
          new_string: "bar",
        )

        assert_match(%r{Error:.*memory://nonexistent not found}, result)
      end

      # ScratchpadMultiEdit tests

      def test_memory_multi_edit_applies_multiple_edits
        @memory.write(file_path: "test", content: "Hello world\nFoo bar", title: "Test")
        @read_tool.execute(file_path: "test")

        edits_json = JSON.generate([
          { old_string: "Hello", new_string: "Hi" },
          { old_string: "world", new_string: "universe" },
          { old_string: "Foo", new_string: "FOO" },
        ])

        result = @multi_edit_tool.execute(file_path: "test", edits_json: edits_json)

        assert_match(/Successfully applied 3 edit/, result)
        assert_match(/Total replacements: 3/, result)

        updated_content = @memory.read(file_path: "test")

        assert_equal("Hi universe\nFOO bar", updated_content)
      end

      def test_memory_multi_edit_edits_are_sequential
        @memory.write(file_path: "test", content: "AAA BBB CCC", title: "Test")
        @read_tool.execute(file_path: "test")

        # First edit changes AAA to XXX
        # Second edit changes XXX to YYY (sees result of first edit)
        edits_json = JSON.generate([
          { old_string: "AAA", new_string: "XXX" },
          { old_string: "XXX", new_string: "YYY" },
        ])

        result = @multi_edit_tool.execute(file_path: "test", edits_json: edits_json)

        assert_match(/Successfully applied 2 edit/, result)

        updated_content = @memory.read(file_path: "test")

        assert_equal("YYY BBB CCC", updated_content)
      end

      def test_memory_multi_edit_with_replace_all
        @memory.write(file_path: "test", content: "foo bar foo baz foo", title: "Test")
        @read_tool.execute(file_path: "test")

        edits_json = JSON.generate([
          { old_string: "foo", new_string: "FOO", replace_all: true },
          { old_string: "bar", new_string: "BAR" },
        ])

        result = @multi_edit_tool.execute(file_path: "test", edits_json: edits_json)

        assert_match(/Successfully applied 2 edit/, result)
        assert_match(/Total replacements: 4/, result) # 3 foo + 1 bar

        updated_content = @memory.read(file_path: "test")

        assert_equal("FOO BAR FOO baz FOO", updated_content)
      end

      def test_memory_multi_edit_requires_read_before_edit
        @memory.write(file_path: "test", content: "Hello world", title: "Test")

        edits_json = JSON.generate([{ old_string: "world", new_string: "universe" }])

        # Should fail WITHOUT read
        result_without_read = @multi_edit_tool.execute(file_path: "test", edits_json: edits_json)

        assert_match(/Error:.*Cannot edit memory entry without reading it first/, result_without_read)

        # Should succeed WITH read
        @read_tool.execute(file_path: "test")
        result_with_read = @multi_edit_tool.execute(file_path: "test", edits_json: edits_json)

        assert_match(/Successfully applied/, result_with_read)
      end

      def test_memory_multi_edit_stops_on_error
        @memory.write(file_path: "test", content: "Hello world", title: "Test")
        @read_tool.execute(file_path: "test")

        # Second edit will fail because "missing" doesn't exist
        edits_json = JSON.generate([
          { old_string: "Hello", new_string: "Hi" },
          { old_string: "missing", new_string: "replacement" },
        ])

        result = @multi_edit_tool.execute(file_path: "test", edits_json: edits_json)

        assert_match(/Error:.*Edit 1.*old_string not found/, result)
        assert_match(/Previous successful edits/, result)
        assert_match(/Edit 0.*Replaced 1/, result)
        assert_match(/All or nothing approach/, result)

        # Content should be unchanged
        content = @memory.read(file_path: "test")

        assert_equal("Hello world", content)
      end

      def test_memory_multi_edit_validates_json
        @memory.write(file_path: "test", content: "test", title: "Test")
        @read_tool.execute(file_path: "test")

        # Invalid JSON
        result = @multi_edit_tool.execute(file_path: "test", edits_json: "not json")

        assert_match(/Error:.*Invalid JSON format/, result)

        # Not an array
        result = @multi_edit_tool.execute(file_path: "test", edits_json: '{"foo":"bar"}')

        assert_match(/Error:.*must be an array/, result)

        # Empty array
        @read_tool.execute(file_path: "test")
        result = @multi_edit_tool.execute(file_path: "test", edits_json: "[]")

        assert_match(/Error:.*cannot be empty/, result)
      end

      def test_memory_multi_edit_validates_edit_structure
        @memory.write(file_path: "test", content: "test", title: "Test")
        @read_tool.execute(file_path: "test")

        # Missing old_string
        edits_json = JSON.generate([{ new_string: "bar" }])
        result = @multi_edit_tool.execute(file_path: "test", edits_json: edits_json)

        assert_match(/Error:.*missing required field 'old_string'/, result)

        # Missing new_string
        edits_json = JSON.generate([{ old_string: "foo" }])
        @read_tool.execute(file_path: "test")
        result = @multi_edit_tool.execute(file_path: "test", edits_json: edits_json)

        assert_match(/Error:.*missing required field 'new_string'/, result)

        # Same old_string and new_string
        edits_json = JSON.generate([{ old_string: "foo", new_string: "foo" }])
        result = @multi_edit_tool.execute(file_path: "test", edits_json: edits_json)

        assert_match(/Error:.*must be different/, result)
      end

      def test_memory_multi_edit_preserves_title
        @memory.write(file_path: "test", content: "Original content", title: "Important Title")
        @read_tool.execute(file_path: "test")

        edits_json = JSON.generate([{ old_string: "Original", new_string: "Updated" }])

        @multi_edit_tool.execute(file_path: "test", edits_json: edits_json)

        entries = @memory.list
        entry = entries.find { |e| e[:path] == "test" }

        assert_equal("Important Title", entry[:title])
      end

      def test_memory_multi_edit_handles_missing_entry
        edits_json = JSON.generate([{ old_string: "foo", new_string: "bar" }])

        @read_tool.execute(file_path: "nonexistent")
        result = @multi_edit_tool.execute(file_path: "nonexistent", edits_json: edits_json)

        assert_match(%r{Error:.*memory://nonexistent not found}, result)
      end
    end
  end
end
