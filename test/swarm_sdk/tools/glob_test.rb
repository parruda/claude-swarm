# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "tmpdir"

module SwarmSDK
  module Tools
    class GlobTest < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
      end

      def teardown
        FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
      end

      def test_glob_tool_finds_files
        File.write(File.join(@temp_dir, "file1.txt"), "")
        File.write(File.join(@temp_dir, "file2.txt"), "")
        File.write(File.join(@temp_dir, "other.rb"), "")

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "#{@temp_dir}/*.txt")

        assert_includes(result, "file1.txt")
        assert_includes(result, "file2.txt")
        refute_includes(result, "other.rb")
      end

      def test_glob_tool_recursive_pattern
        subdir = File.join(@temp_dir, "subdir")
        FileUtils.mkdir_p(subdir)
        File.write(File.join(@temp_dir, "top.rb"), "")
        File.write(File.join(subdir, "nested.rb"), "")

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "#{@temp_dir}/**/*.rb")

        assert_includes(result, "top.rb")
        assert_includes(result, "nested.rb")
      end

      def test_glob_tool_no_matches
        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "#{@temp_dir}/*.nonexistent")

        assert_includes(result, "No matches found")
      end

      def test_glob_tool_invalid_directory
        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "/nonexistent/dir/*.txt")

        assert_includes(result, "No matches found")
      end

      def test_glob_tool_finds_directories
        subdir1 = File.join(@temp_dir, "dir1")
        subdir2 = File.join(@temp_dir, "dir2")
        FileUtils.mkdir_p(subdir1)
        FileUtils.mkdir_p(subdir2)
        File.write(File.join(@temp_dir, "file.txt"), "")

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "#{@temp_dir}/*/")

        assert_includes(result, "dir1")
        assert_includes(result, "dir2")
        refute_includes(result, "file.txt")
      end

      def test_glob_tool_filters_dot_directories
        subdir = File.join(@temp_dir, "real_dir")
        FileUtils.mkdir_p(subdir)

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "#{@temp_dir}/*/")

        # Should include real directory
        assert_includes(result, "real_dir")
        # Should not include . or .. references
        refute_match(%r{/\.\/$}, result)
        refute_match(%r{/\.\.\/$}, result)
      end

      def test_glob_tool_finds_both_files_and_directories
        subdir = File.join(@temp_dir, "subdir")
        FileUtils.mkdir_p(subdir)
        File.write(File.join(@temp_dir, "file.txt"), "")

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "#{@temp_dir}/*")

        assert_includes(result, "subdir")
        assert_includes(result, "file.txt")
      end

      def test_glob_tool_treats_absolute_patterns_as_absolute
        # Create a file in system temp
        system_temp = Dir.tmpdir
        temp_file = File.join(system_temp, "glob_test_#{Process.pid}.txt")
        File.write(temp_file, "test")

        begin
          tool = Glob.new(directory: @temp_dir)

          # Absolute pattern searches absolute path
          result = tool.execute(
            pattern: File.join(system_temp, "*glob_test*.txt"),
          )

          assert_includes(result, temp_file)
        ensure
          File.delete(temp_file) if File.exist?(temp_file)
        end
      end

      def test_glob_tool_relative_patterns_work_from_cwd
        # Create file in @temp_dir/subdir
        subdir = File.join(@temp_dir, "subdir")
        FileUtils.mkdir_p(subdir)
        File.write(File.join(subdir, "file.txt"), "")

        tool = Glob.new(directory: @temp_dir)

        # Full path pattern
        result = tool.execute(pattern: "#{@temp_dir}/subdir/*.txt")

        assert_includes(result, "file.txt")
      end

      def test_glob_tool_with_nil_pattern
        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: nil)

        assert_includes(result, "Error: pattern is required")
      end

      def test_glob_tool_with_blank_pattern
        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "   ")

        assert_includes(result, "Error: pattern is required")
      end

      def test_glob_tool_with_empty_pattern
        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "")

        assert_includes(result, "Error: pattern is required")
      end

      def test_glob_tool_truncates_large_result_sets
        # Create more than MAX_RESULTS files
        1100.times do |i|
          File.write(File.join(@temp_dir, "file#{i}.txt"), "")
        end

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "#{@temp_dir}/*.txt")

        # Should include truncation message
        assert_includes(result, "Results limited to first 1000 matches")
        assert_includes(result, "Consider using a more specific pattern")
      end

      def test_glob_tool_singular_match_message
        File.write(File.join(@temp_dir, "single.txt"), "")

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "#{@temp_dir}/single.txt")

        assert_includes(result, "Found 1 match for")
        refute_includes(result, "matches")
      end

      def test_glob_tool_plural_matches_message
        File.write(File.join(@temp_dir, "file1.txt"), "")
        File.write(File.join(@temp_dir, "file2.txt"), "")

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "#{@temp_dir}/*.txt")

        assert_includes(result, "Found 2 matches for")
      end

      def test_glob_with_path_parameter
        File.write(File.join(@temp_dir, "file1.txt"), "")
        File.write(File.join(@temp_dir, "file2.txt"), "")
        File.write(File.join(@temp_dir, "other.rb"), "")

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "*.txt", path: @temp_dir)

        assert_includes(result, "file1.txt")
        assert_includes(result, "file2.txt")
        refute_includes(result, "other.rb")
      end

      def test_glob_with_path_parameter_recursive
        subdir = File.join(@temp_dir, "subdir")
        FileUtils.mkdir_p(subdir)
        File.write(File.join(@temp_dir, "top.rb"), "")
        File.write(File.join(subdir, "nested.rb"), "")

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "**/*.rb", path: @temp_dir)

        assert_includes(result, "top.rb")
        assert_includes(result, "nested.rb")
      end

      def test_glob_with_nonexistent_path
        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "*.txt", path: "/nonexistent/path")

        assert_includes(result, "Path does not exist")
      end

      def test_glob_with_path_not_directory
        temp_file = File.join(@temp_dir, "not_a_dir.txt")
        File.write(temp_file, "test")

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "*.txt", path: temp_file)

        assert_includes(result, "Path is not a directory")
      end

      def test_glob_with_undefined_path_string
        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "*.txt", path: "undefined")

        assert_includes(result, "Invalid path value")
        assert_includes(result, "Omit the path parameter")
      end

      def test_glob_with_null_path_string
        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(pattern: "*.txt", path: "null")

        assert_includes(result, "Invalid path value")
        assert_includes(result, "Omit the path parameter")
      end

      def test_glob_with_empty_path_string
        # Empty string should use current working directory
        File.write(File.join(Dir.pwd, "test_glob_temp.txt"), "test")

        begin
          tool = Glob.new(directory: @temp_dir)
          result = tool.execute(pattern: "test_glob_temp.txt", path: "")

          assert_includes(result, "test_glob_temp.txt")
        ensure
          File.delete(File.join(Dir.pwd, "test_glob_temp.txt")) if File.exist?(File.join(Dir.pwd, "test_glob_temp.txt"))
        end
      end

      def test_glob_with_nil_path_uses_cwd
        # nil path should use current working directory
        File.write(File.join(Dir.pwd, "test_glob_temp2.txt"), "test")

        begin
          tool = Glob.new(directory: @temp_dir)
          result = tool.execute(pattern: "test_glob_temp2.txt", path: nil)

          assert_includes(result, "test_glob_temp2.txt")
        ensure
          File.delete(File.join(Dir.pwd, "test_glob_temp2.txt")) if File.exist?(File.join(Dir.pwd, "test_glob_temp2.txt"))
        end
      end

      def test_glob_with_absolute_pattern_ignores_path
        # When pattern is absolute, it should be used directly
        # even if a different (valid) path is provided
        File.write(File.join(@temp_dir, "absolute.txt"), "")

        # Create another directory that won't have the file
        other_dir = File.join(@temp_dir, "other")
        FileUtils.mkdir_p(other_dir)

        tool = Glob.new(directory: @temp_dir)
        result = tool.execute(
          pattern: File.join(@temp_dir, "absolute.txt"),
          path: other_dir, # Valid path, but doesn't contain the file
        )

        # Should find the file because pattern is absolute
        # (absolute patterns ignore the path parameter)
        assert_includes(result, "absolute.txt")
      end

      def test_glob_with_relative_path
        subdir = File.join(@temp_dir, "subdir")
        FileUtils.mkdir_p(subdir)
        File.write(File.join(subdir, "file.txt"), "")

        # Save current dir and change to @temp_dir
        original_dir = Dir.pwd
        Dir.chdir(@temp_dir)

        begin
          tool = Glob.new(directory: @temp_dir)
          result = tool.execute(pattern: "*.txt", path: "subdir")

          assert_includes(result, "file.txt")
        ensure
          Dir.chdir(original_dir)
        end
      end
    end
  end
end
