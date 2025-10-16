# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "tmpdir"

module SwarmSDK
  module Tools
    class EditTest < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @test_file = File.join(@temp_dir, "test.txt")
      end

      def teardown
        FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
        Stores::ReadTracker.clear_all
      end

      def test_edit_tool_replaces_exact_match
        File.write(@test_file, "Hello, World!\nGoodbye, World!\n")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          old_string: "Hello",
          new_string: "Hi",
        )

        content = File.read(@test_file)

        assert_equal("Hi, World!\nGoodbye, World!\n", content)
        assert_includes(result, "Successfully replaced")
      end

      def test_edit_tool_fails_without_read
        File.write(@test_file, "Hello, World!")

        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          old_string: "Hello",
          new_string: "Hi",
        )

        assert_includes(result, "Error")
        assert_includes(result, "reading it first")
        assert_includes(result, "Read tool")

        # File should NOT be modified
        assert_equal("Hello, World!", File.read(@test_file))
      end

      def test_edit_tool_multiple_occurrences_error
        File.write(@test_file, "foo\nfoo\nfoo\n")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          old_string: "foo",
          new_string: "bar",
        )

        assert_includes(result, "Error")
        assert_includes(result, "3 occurrences")
      end

      def test_edit_tool_replace_all
        File.write(@test_file, "foo\nfoo\nfoo\n")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          old_string: "foo",
          new_string: "bar",
          replace_all: true,
        )

        content = File.read(@test_file)

        assert_equal("bar\nbar\nbar\n", content)
        assert_includes(result, "3 occurrence(s)")
      end

      def test_edit_tool_string_not_found
        File.write(@test_file, "Hello, World!")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          old_string: "nonexistent",
          new_string: "replacement",
        )

        assert_includes(result, "Error")
        assert_includes(result, "not found")
      end

      def test_edit_tool_same_strings_error
        File.write(@test_file, "test")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          old_string: "test",
          new_string: "test",
        )

        assert_includes(result, "Error")
        assert_includes(result, "must be different")
      end

      def test_edit_tool_agent_isolation
        File.write(@test_file, "Hello World")

        # Agent 1 reads
        Read.new(agent_name: :agent1, directory: @temp_dir).execute(file_path: @test_file)

        # Agent 1 can edit
        result1 = Edit.new(agent_name: :agent1, directory: @temp_dir).execute(
          file_path: @test_file,
          old_string: "Hello",
          new_string: "Hi",
        )

        assert_includes(result1, "Successfully")

        # Agent 2 cannot edit (hasn't read)
        result2 = Edit.new(agent_name: :agent2, directory: @temp_dir).execute(
          file_path: @test_file,
          old_string: "Hi",
          new_string: "Hey",
        )

        assert_includes(result2, "Error")
        assert_includes(result2, "reading it first")
      end

      def test_edit_tool_with_nil_file_path
        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: nil, old_string: "old", new_string: "new")

        assert_includes(result, "Error: file_path is required")
      end

      def test_edit_tool_with_blank_file_path
        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: "   ", old_string: "old", new_string: "new")

        assert_includes(result, "Error: file_path is required")
      end

      def test_edit_tool_with_empty_file_path
        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: "", old_string: "old", new_string: "new")

        assert_includes(result, "Error: file_path is required")
      end

      def test_edit_tool_with_empty_old_string
        File.write(@test_file, "test content")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: @test_file, old_string: "", new_string: "new")

        assert_includes(result, "Error")
        assert_includes(result, "old_string is required")
      end

      def test_edit_tool_with_nil_old_string
        File.write(@test_file, "test content")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: @test_file, old_string: nil, new_string: "new")

        assert_includes(result, "Error")
        assert_includes(result, "old_string is required")
      end

      def test_edit_tool_with_nil_new_string
        File.write(@test_file, "test content")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = Edit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: @test_file, old_string: "test", new_string: nil)

        assert_includes(result, "Error")
        assert_includes(result, "new_string is required")
      end
    end
  end
end
