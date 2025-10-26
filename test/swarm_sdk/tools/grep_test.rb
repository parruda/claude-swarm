# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "tmpdir"

module SwarmSDK
  module Tools
    class GrepTest < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @test_file = File.join(@temp_dir, "test.txt")
      end

      def teardown
        FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
      end

      def test_grep_tool_finds_pattern
        File.write(@test_file, "line 1 foo\nline 2 bar\nline 3 foo\n")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "foo",
          path: @test_file,
          output_mode: "content",
        )

        assert_includes(result, "line 1 foo")
        assert_includes(result, "line 3 foo")
        refute_includes(result, "line 2 bar")
      end

      def test_grep_tool_files_with_matches
        File.write(@test_file, "contains pattern")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "pattern",
          path: @temp_dir,
          output_mode: "files_with_matches",
        )

        assert_includes(result, @test_file)
      end

      def test_grep_tool_no_matches
        File.write(@test_file, "nothing here")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "nonexistent",
          path: @test_file,
        )

        assert_includes(result, "No matches found")
      end

      def test_grep_tool_case_insensitive
        File.write(@test_file, "HELLO world")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "hello",
          path: @test_file,
          output_mode: "content",
          case_insensitive: true,
        )

        assert_includes(result, "HELLO")
      end

      def test_grep_tool_with_context
        File.write(@test_file, "line 1\nline 2 match\nline 3\n")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "match",
          path: @test_file,
          output_mode: "content",
          context: 1,
        )

        assert_includes(result, "line 1")
        assert_includes(result, "line 2 match")
        assert_includes(result, "line 3")
      end

      def test_grep_tool_with_nil_path_defaults_to_current_dir
        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "test",
          path: nil,
        )

        # Should search in current directory, not error
        # Result will depend on what's in current directory
        refute_includes(result, "Error: path is required")
      end

      def test_grep_tool_with_blank_path_defaults_to_current_dir
        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "test",
          path: "   ",
        )

        # Should search in current directory, not error
        refute_includes(result, "Error: path is required")
      end

      def test_grep_tool_with_empty_path_defaults_to_current_dir
        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "test",
          path: "",
        )

        # Should search in current directory, not error
        refute_includes(result, "Error: path is required")
      end

      def test_grep_tool_with_empty_type_parameter
        File.write(@test_file, "test content")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "test",
          path: @temp_dir,
          type: "",
          glob: "*.txt",
        )

        # Should work without "unrecognized file type" error
        refute_includes(result, "unrecognized file type")
        refute_includes(result, "Error:")
      end

      def test_grep_tool_with_empty_glob_parameter
        File.write(@test_file, "test content")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "test",
          path: @temp_dir,
          glob: "",
        )

        # Should work without error
        refute_includes(result, "Error:")
      end

      def test_grep_tool_count_output_mode
        File.write(@test_file, "foo\nbar\nfoo\n")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "foo",
          path: @test_file,
          output_mode: "count",
        )

        # Should show match count
        assert_includes(result, "2")
      end

      def test_grep_tool_invalid_output_mode
        File.write(@test_file, "test content")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "test",
          path: @test_file,
          output_mode: "invalid",
        )

        assert_includes(result, "InputValidationError")
        assert_includes(result, "output_mode must be one of")
      end

      def test_grep_tool_multiline_mode
        File.write(@test_file, "start\nmiddle\nend")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "start.*end",
          path: @test_file,
          output_mode: "content",
          multiline: true,
        )

        # Multiline should match across lines
        assert_includes(result, "start")
      end

      def test_grep_tool_with_line_numbers
        File.write(@test_file, "line 1\nline 2 match\nline 3\n")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "match",
          path: @test_file,
          output_mode: "content",
          show_line_numbers: true,
        )

        # Should include line numbers
        assert_match(/2.*match/, result)
      end

      def test_grep_tool_with_context_before
        File.write(@test_file, "line 1\nline 2\nline 3 match\nline 4\n")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "match",
          path: @test_file,
          output_mode: "content",
          context_before: 1,
        )

        assert_includes(result, "line 2")
        assert_includes(result, "line 3 match")
      end

      def test_grep_tool_with_context_after
        File.write(@test_file, "line 1\nline 2 match\nline 3\nline 4\n")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "match",
          path: @test_file,
          output_mode: "content",
          context_after: 1,
        )

        assert_includes(result, "line 2 match")
        assert_includes(result, "line 3")
      end

      def test_grep_tool_with_context_both
        File.write(@test_file, "line 1\nline 2\nline 3 match\nline 4\nline 5\n")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "match",
          path: @test_file,
          output_mode: "content",
          context: 1,
        )

        assert_includes(result, "line 2")
        assert_includes(result, "line 3 match")
        assert_includes(result, "line 4")
      end

      def test_grep_tool_head_limit_with_content
        # Write many matching lines
        content = (1..20).map { |i| "match line #{i}" }.join("\n")
        File.write(@test_file, content)

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "match",
          path: @test_file,
          output_mode: "content",
          head_limit: 5,
        )

        assert_includes(result, "match line 1")
        assert_includes(result, "match line 5")
        refute_includes(result, "match line 10")
        assert_includes(result, "Output limited to first 5 lines")
      end

      def test_grep_tool_head_limit_with_files_with_matches
        # Create multiple matching files
        10.times do |i|
          file = File.join(@temp_dir, "file#{i}.txt")
          File.write(file, "match content")
        end

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "match",
          path: @temp_dir,
          output_mode: "files_with_matches",
          head_limit: 3,
        )

        # Should include the limit reminder when results exceed limit
        assert_includes(result, "Output limited to first 3 lines")
        # Check that head_limit parameter works (reduces output vs no limit)
        assert_operator(result.length, :<, 1000, "Output should be limited")
      end

      def test_grep_tool_usage_reminder_for_files_with_matches
        File.write(@test_file, "test content")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "test",
          path: @test_file,
          output_mode: "files_with_matches",
        )

        assert_includes(result, "<system-reminder>")
        assert_includes(result, "output_mode: 'content'")
      end

      def test_grep_tool_no_usage_reminder_for_content_mode
        File.write(@test_file, "test content")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "test",
          path: @test_file,
          output_mode: "content",
        )

        refute_includes(result, "To see the actual matching lines")
      end

      def test_grep_tool_empty_result_with_content_mode
        File.write(@test_file, "test content")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "nonexistent",
          path: @test_file,
          output_mode: "content",
        )

        assert_includes(result, "No matches found")
      end

      def test_grep_tool_count_mode_usage_reminder
        File.write(@test_file, "test content")

        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(
          pattern: "test",
          path: @test_file,
          output_mode: "count",
        )

        assert_includes(result, "<system-reminder>")
        assert_includes(result, "output_mode: 'content'")
      end

      def test_grep_tool_error_exit_code_with_stderr
        tool = Grep.new(directory: @temp_dir)
        # Try to grep in a non-existent directory (will cause error exit code 2)
        result = tool.execute(
          pattern: "test",
          path: "/nonexistent/directory/that/does/not/exist",
          output_mode: "content",
        )

        assert_includes(result, "Error")
        assert_includes(result, "ripgrep error")
      end

      def test_grep_tool_with_nil_pattern
        tool = Grep.new(directory: @temp_dir)
        result = tool.execute(pattern: nil, path: @temp_dir)

        assert_includes(result, "Error: pattern is required")
      end
    end
  end
end
