# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Tools
    class ScratchpadToolsTest < Minitest::Test
      def setup
        @scratchpad = Tools::Stores::Scratchpad.new
        @write_tool = ScratchpadWrite.create_for_scratchpad(@scratchpad)
        @read_tool = ScratchpadRead.create_for_scratchpad(@scratchpad)
        @list_tool = ScratchpadList.create_for_scratchpad(@scratchpad)
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

      # ScratchpadList tests

      def test_scratchpad_list_returns_all_entries
        @scratchpad.write(file_path: "a/1", content: "A1", title: "Entry A1")
        @scratchpad.write(file_path: "a/2", content: "A2", title: "Entry A2")
        @scratchpad.write(file_path: "b/1", content: "B1", title: "Entry B1")

        result = @list_tool.execute

        assert_match(/Scratchpad contents \(3 entries\):/, result)
        assert_match(%r{scratchpad://a/1 - "Entry A1"}, result)
        assert_match(%r{scratchpad://a/2 - "Entry A2"}, result)
        assert_match(%r{scratchpad://b/1 - "Entry B1"}, result)
      end

      def test_scratchpad_list_filters_by_prefix
        @scratchpad.write(file_path: "parallel/batch1/task_0", content: "T0", title: "Task 0")
        @scratchpad.write(file_path: "parallel/batch1/task_1", content: "T1", title: "Task 1")
        @scratchpad.write(file_path: "analysis/report", content: "R", title: "Report")

        result = @list_tool.execute(prefix: "parallel/batch1/")

        assert_match(/Scratchpad contents \(2 entries\):/, result)
        assert_match(%r{scratchpad://parallel/batch1/task_0 - "Task 0"}, result)
        assert_match(%r{scratchpad://parallel/batch1/task_1 - "Task 1"}, result)
        refute_match(%r{analysis/report}, result)
      end

      def test_scratchpad_list_shows_sizes
        @scratchpad.write(file_path: "small", content: "x" * 100, title: "Small")
        @scratchpad.write(file_path: "large", content: "x" * 50_000, title: "Large")

        result = @list_tool.execute

        assert_match(%r{scratchpad://small.*\(100B\)}, result)
        assert_match(%r{scratchpad://large.*\(50.0KB\)}, result)
      end

      def test_scratchpad_list_returns_empty_message
        result = @list_tool.execute

        assert_equal("Scratchpad is empty", result)
      end

      def test_scratchpad_list_returns_no_matches_message
        @scratchpad.write(file_path: "a/1", content: "A1", title: "Entry A1")

        result = @list_tool.execute(prefix: "b/")

        assert_equal("No entries found with prefix 'b/'", result)
      end

      def test_scratchpad_list_shows_singular_entry
        @scratchpad.write(file_path: "test", content: "x", title: "Test")

        result = @list_tool.execute

        assert_match(/Scratchpad contents \(1 entry\):/, result)
      end

      def test_scratchpad_list_with_nil_prefix
        @scratchpad.write(file_path: "a/1", content: "A1", title: "Entry A1")
        @scratchpad.write(file_path: "b/1", content: "B1", title: "Entry B1")

        result = @list_tool.execute(prefix: nil)

        assert_match(/Scratchpad contents \(2 entries\):/, result)
        assert_match(%r{scratchpad://a/1}, result)
        assert_match(%r{scratchpad://b/1}, result)
      end

      def test_scratchpad_list_with_empty_prefix
        @scratchpad.write(file_path: "a/1", content: "A1", title: "Entry A1")
        @scratchpad.write(file_path: "b/1", content: "B1", title: "Entry B1")

        result = @list_tool.execute(prefix: "")

        # Empty prefix should list all entries
        assert_match(/Scratchpad contents \(2 entries\):/, result)
        assert_match(%r{scratchpad://a/1}, result)
        assert_match(%r{scratchpad://b/1}, result)
      end

      # Integration tests

      def test_scratchpad_tools_share_same_storage
        # Write using write tool
        @write_tool.execute(file_path: "shared", content: "Shared content", title: "Shared")

        # Read using read tool
        result = @read_tool.execute(file_path: "shared")

        assert_equal("Shared content", result)

        # List using list tool
        list_result = @list_tool.execute

        assert_match(%r{scratchpad://shared - "Shared"}, list_result)
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

        result = @list_tool.execute

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
    end
  end
end
