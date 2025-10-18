# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Tools
    class ScratchpadToolsTest < Minitest::Test
      def setup
        @scratchpad = Tools::Stores::Scratchpad.new
        @write_tool = ScratchpadWrite.create_for_scratchpad(@scratchpad)
        @read_tool = ScratchpadRead.create_for_scratchpad(@scratchpad)
        @glob_tool = ScratchpadGlob.create_for_scratchpad(@scratchpad)
        @grep_tool = ScratchpadGrep.create_for_scratchpad(@scratchpad)
      end

      # ScratchpadWrite tests

      def test_scratchpad_write_stores_content
        result = @write_tool.execute(
          file_path: "test/path",
          content: "Test content",
          title: "Test title",
        )

        assert_match(%r{Stored at scratchpad://test/path}, result)
        assert_match(/\(12B\)/, result) # "Test content" is 12 bytes
      end

      def test_scratchpad_write_returns_formatted_size
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

      def test_scratchpad_write_handles_errors
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

      def test_scratchpad_write_handles_size_limit_error
        large_content = "x" * (Tools::Stores::Scratchpad::MAX_ENTRY_SIZE + 1)

        result = @write_tool.execute(file_path: "test", content: large_content, title: "Too big")

        assert_match(/Error:/, result)
        assert_match(/exceeds maximum size/, result)
      end

      # ScratchpadRead tests

      def test_scratchpad_read_returns_content
        @scratchpad.write(file_path: "test/path", content: "Expected content", title: "Test")

        result = @read_tool.execute(file_path: "test/path")

        assert_equal("Expected content", result)
      end

      def test_scratchpad_read_handles_missing_path
        result = @read_tool.execute(file_path: "nonexistent")

        assert_match(/Error:/, result)
        assert_match(%r{scratchpad://nonexistent not found}, result)
      end

      def test_scratchpad_read_handles_empty_path
        result = @read_tool.execute(file_path: "")

        assert_match(/Error:/, result)
        assert_match(/file_path is required/, result)
      end

      # Integration tests

      def test_scratchpad_tools_share_same_storage
        # Write using write tool
        @write_tool.execute(file_path: "shared", content: "Shared content", title: "Shared")

        # Read using read tool
        result = @read_tool.execute(file_path: "shared")

        assert_equal("Shared content", result)

        # Glob using glob tool
        glob_result = @glob_tool.execute(pattern: "shared")

        assert_match(%r{scratchpad://shared - "Shared"}, glob_result)
      end

      def test_scratchpad_tools_work_with_complex_paths
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
          assert_match(%r{scratchpad://#{Regexp.escape(path)}}, result)
        end
      end

      def test_scratchpad_tools_handle_unicode_content
        unicode_content = "Hello 🌍! Привет мир! 你好世界!"

        @write_tool.execute(file_path: "unicode", content: unicode_content, title: "Unicode test")

        result = @read_tool.execute(file_path: "unicode")

        assert_equal(unicode_content, result)
      end

      def test_multiple_tool_instances_share_same_scratchpad
        # Create another set of tools for the same scratchpad
        write_tool2 = ScratchpadWrite.create_for_scratchpad(@scratchpad)
        read_tool2 = ScratchpadRead.create_for_scratchpad(@scratchpad)

        # Write with first tool
        @write_tool.execute(file_path: "test", content: "Original", title: "Test")

        # Read with second tool
        result = read_tool2.execute(file_path: "test")

        assert_equal("Original", result)

        # Update with second tool
        write_tool2.execute(file_path: "test", content: "Updated", title: "Updated")

        # Read with first tool
        result = @read_tool.execute(file_path: "test")

        assert_equal("Updated", result)
      end

      def test_scratchpad_write_with_nil_file_path
        result = @write_tool.execute(file_path: nil, content: "test", title: "Test")

        assert_includes(result, "Error: file_path is required")
      end

      def test_scratchpad_write_with_blank_file_path
        result = @write_tool.execute(file_path: "   ", content: "test", title: "Test")

        assert_includes(result, "Error: file_path is required")
      end

      def test_scratchpad_write_with_empty_file_path
        result = @write_tool.execute(file_path: "", content: "test", title: "Test")

        assert_includes(result, "Error: file_path is required")
      end

      def test_scratchpad_read_with_nil_file_path
        result = @read_tool.execute(file_path: nil)

        assert_includes(result, "Error: file_path is required")
      end

      def test_scratchpad_read_with_blank_file_path
        result = @read_tool.execute(file_path: "   ")

        assert_includes(result, "Error: file_path is required")
      end

      def test_scratchpad_read_with_empty_file_path
        result = @read_tool.execute(file_path: "")

        assert_includes(result, "Error: file_path is required")
      end

      # ScratchpadGlob tests

      def test_scratchpad_glob_returns_matching_entries
        @scratchpad.write(file_path: "parallel/batch1/task_0", content: "T0", title: "Task 0")
        @scratchpad.write(file_path: "parallel/batch1/task_1", content: "T1", title: "Task 1")
        @scratchpad.write(file_path: "parallel/batch2/task_0", content: "T2", title: "Task 2")
        @scratchpad.write(file_path: "analysis/report", content: "R", title: "Report")

        result = @glob_tool.execute(pattern: "parallel/*/task_0")

        assert_match(%r{Scratchpad entries matching 'parallel/\*/task_0' \(2 entries\):}, result)
        assert_match(%r{scratchpad://parallel/batch1/task_0 - "Task 0"}, result)
        assert_match(%r{scratchpad://parallel/batch2/task_0 - "Task 2"}, result)
        refute_match(/analysis/, result)
      end

      def test_scratchpad_glob_with_recursive_pattern
        @scratchpad.write(file_path: "parallel/batch1/task_0", content: "T0", title: "Task 0")
        @scratchpad.write(file_path: "parallel/batch1/sub/task_1", content: "T1", title: "Task 1")
        @scratchpad.write(file_path: "analysis/report", content: "R", title: "Report")

        result = @glob_tool.execute(pattern: "parallel/**")

        assert_match(%r{Scratchpad entries matching 'parallel/\*\*' \(2 entries\):}, result)
        assert_match(%r{scratchpad://parallel/batch1/task_0}, result)
        assert_match(%r{scratchpad://parallel/batch1/sub/task_1}, result)
      end

      def test_scratchpad_glob_no_matches
        @scratchpad.write(file_path: "a/1", content: "A1", title: "Entry A1")

        result = @glob_tool.execute(pattern: "b/*")

        assert_equal("No entries found matching pattern 'b/*'", result)
      end

      def test_scratchpad_glob_shows_sizes
        @scratchpad.write(file_path: "test/small", content: "x" * 100, title: "Small")
        @scratchpad.write(file_path: "test/large", content: "x" * 50_000, title: "Large")

        result = @glob_tool.execute(pattern: "test/*")

        assert_match(%r{scratchpad://test/small.*\(100B\)}, result)
        assert_match(%r{scratchpad://test/large.*\(50.0KB\)}, result)
      end

      def test_scratchpad_glob_handles_errors
        result = @glob_tool.execute(pattern: "")

        assert_match(/Error: pattern is required/, result)
      end

      # ScratchpadGrep tests

      def test_scratchpad_grep_files_with_matches
        @scratchpad.write(file_path: "a", content: "Hello world", title: "A")
        @scratchpad.write(file_path: "b", content: "Goodbye world", title: "B")
        @scratchpad.write(file_path: "c", content: "Nothing here", title: "C")

        result = @grep_tool.execute(pattern: "world")

        assert_match(/Scratchpad entries matching 'world' \(2 entries\):/, result)
        assert_match(%r{scratchpad://a}, result)
        assert_match(%r{scratchpad://b}, result)
        refute_match(%r{scratchpad://c}, result)
      end

      def test_scratchpad_grep_case_insensitive
        @scratchpad.write(file_path: "a", content: "Hello World", title: "A")
        @scratchpad.write(file_path: "b", content: "hello world", title: "B")

        # Case sensitive (default)
        result = @grep_tool.execute(pattern: "hello")

        assert_match(/Scratchpad entries matching 'hello' \(1 entry\):/, result)
        assert_match(%r{scratchpad://b}, result)
        refute_match(%r{scratchpad://a}, result)

        # Case insensitive
        result = @grep_tool.execute(pattern: "hello", case_insensitive: true)

        assert_match(/Scratchpad entries matching 'hello' \(2 entries\):/, result)
        assert_match(%r{scratchpad://a}, result)
        assert_match(%r{scratchpad://b}, result)
      end

      def test_scratchpad_grep_content_mode
        @scratchpad.write(file_path: "test", content: "Line 1: error\nLine 2: ok\nLine 3: error", title: "Test")

        result = @grep_tool.execute(pattern: "error", output_mode: "content")

        assert_match(/Scratchpad entries matching 'error' \(1 entry, 2 matches\):/, result)
        assert_match(%r{scratchpad://test:}, result)
        assert_match(/1: Line 1: error/, result)
        assert_match(/3: Line 3: error/, result)
      end

      def test_scratchpad_grep_count_mode
        @scratchpad.write(file_path: "a", content: "foo bar foo", title: "A")
        @scratchpad.write(file_path: "b", content: "foo", title: "B")

        result = @grep_tool.execute(pattern: "foo", output_mode: "count")

        assert_match(/Scratchpad entries matching 'foo' \(2 entries, 3 total matches\):/, result)
        assert_match(%r{scratchpad://a: 2 matches}, result)
        assert_match(%r{scratchpad://b: 1 match}, result)
      end

      def test_scratchpad_grep_no_matches
        @scratchpad.write(file_path: "test", content: "hello", title: "Test")

        result = @grep_tool.execute(pattern: "goodbye")

        assert_equal("No matches found for pattern 'goodbye'", result)
      end

      def test_scratchpad_grep_handles_errors
        result = @grep_tool.execute(pattern: "")

        assert_match(/Error: pattern is required/, result)
      end

      def test_scratchpad_grep_invalid_regex
        @scratchpad.write(file_path: "test", content: "test", title: "Test")

        result = @grep_tool.execute(pattern: "[invalid")

        assert_match(/Error: Invalid regex pattern/, result)
      end

      def test_scratchpad_grep_invalid_output_mode
        @scratchpad.write(file_path: "test", content: "test", title: "Test")

        result = @grep_tool.execute(pattern: "test", output_mode: "invalid")

        assert_match(/Error: Invalid output_mode/, result)
      end
    end
  end
end
