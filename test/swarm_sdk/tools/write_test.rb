# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "tmpdir"

module SwarmSDK
  module Tools
    class WriteTest < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @test_file = File.join(@temp_dir, "test.txt")
      end

      def teardown
        FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
        Stores::ReadTracker.clear_all
      end

      def test_write_tool_creates_file
        tool = Write.new(agent_name: :test_agent, directory: @temp_dir)
        content = "Hello, World!"
        result = tool.execute(file_path: @test_file, content: content)

        assert_path_exists(@test_file)
        assert_equal(content, File.read(@test_file))
        assert_includes(result, "Successfully")
        assert_includes(result, "created")
      end

      def test_write_tool_overwrites_file_after_read
        File.write(@test_file, "original content")

        # Read the file first
        read_tool = Read.new(agent_name: :test_agent, directory: @temp_dir)
        read_tool.execute(file_path: @test_file)

        # Now write should work
        tool = Write.new(agent_name: :test_agent, directory: @temp_dir)
        new_content = "new content"
        result = tool.execute(file_path: @test_file, content: new_content)

        assert_equal(new_content, File.read(@test_file))
        assert_includes(result, "overwrote")
        assert_includes(result, "<system-reminder>")
      end

      def test_write_tool_fails_without_read
        File.write(@test_file, "original content")

        # Try to write without reading first
        tool = Write.new(agent_name: :test_agent, directory: @temp_dir)
        new_content = "new content"
        result = tool.execute(file_path: @test_file, content: new_content)

        # Should fail with read-first error
        assert_includes(result, "Error")
        assert_includes(result, "reading it first")
        assert_includes(result, "Read tool")

        # File should NOT be modified
        assert_equal("original content", File.read(@test_file))
      end

      def test_write_tool_creates_parent_directory
        nested_file = File.join(@temp_dir, "subdir", "nested.txt")

        tool = Write.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: nested_file, content: "test")

        assert_path_exists(nested_file)
        assert_includes(result, "Successfully")
      end

      def test_write_tool_empty_path_error
        tool = Write.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: "", content: "test")

        assert_includes(result, "Error")
        assert_includes(result, "required")
      end

      def test_write_tool_agent_isolation
        File.write(@test_file, "original content")

        # Agent 1 reads the file
        read_tool = Read.new(agent_name: :agent1, directory: @temp_dir)
        read_tool.execute(file_path: @test_file)

        # Agent 1 can write
        write_tool1 = Write.new(agent_name: :agent1, directory: @temp_dir)
        result1 = write_tool1.execute(file_path: @test_file, content: "agent1 content")

        assert_includes(result1, "Successfully")

        # Agent 2 cannot write (hasn't read)
        write_tool2 = Write.new(agent_name: :agent2, directory: @temp_dir)
        result2 = write_tool2.execute(file_path: @test_file, content: "agent2 content")

        assert_includes(result2, "Error")
        assert_includes(result2, "reading it first")
      end

      def test_write_tool_with_nil_file_path
        tool = Write.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: nil, content: "test")

        assert_includes(result, "Error: file_path is required")
      end

      def test_write_tool_with_blank_file_path
        tool = Write.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: "   ", content: "test")

        assert_includes(result, "Error: file_path is required")
      end

      def test_write_tool_with_empty_file_path
        tool = Write.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: "", content: "test")

        assert_includes(result, "Error: file_path is required")
      end

      def test_write_tool_with_nil_content
        tool = Write.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: @test_file, content: nil)

        assert_includes(result, "Error")
      end

      def test_write_tool_with_empty_content
        tool = Write.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: @test_file, content: "")

        # Empty content is allowed (creates empty file)
        assert_includes(result, "Successfully")
      end
    end
  end
end
