# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "tmpdir"

module SwarmSDK
  module Tools
    class MultiEditTest < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        @test_file = File.join(@temp_dir, "test.txt")
      end

      def teardown
        FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
        Stores::ReadTracker.clear_all
      end

      def test_multi_edit_applies_sequential_edits
        File.write(@test_file, "Hello World\nFoo Bar\n")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          edits_json: '[{"old_string":"Hello","new_string":"Hi"},{"old_string":"World","new_string":"Earth"},{"old_string":"Foo","new_string":"Baz"}]',
        )

        content = File.read(@test_file)

        assert_equal("Hi Earth\nBaz Bar\n", content)
        assert_includes(result, "Successfully applied 3 edit(s)")
        assert_includes(result, "Total replacements: 3")
      end

      def test_multi_edit_fails_without_read
        File.write(@test_file, "Hello World")

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          edits_json: '[{"old_string":"Hello","new_string":"Hi"}]',
        )

        assert_includes(result, "Error")
        assert_includes(result, "reading it first")
        assert_includes(result, "Read tool")

        # File should NOT be modified
        assert_equal("Hello World", File.read(@test_file))
      end

      def test_multi_edit_later_edits_see_earlier_changes
        File.write(@test_file, "Original Text\n")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          edits_json: '[{"old_string":"Original","new_string":"Modified"},{"old_string":"Modified","new_string":"Final"}]',
        )

        content = File.read(@test_file)

        assert_equal("Final Text\n", content)
        assert_includes(result, "Successfully applied 2 edit(s)")
      end

      def test_multi_edit_with_replace_all
        File.write(@test_file, "foo foo foo\n")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          edits_json: '[{"old_string":"foo","new_string":"bar","replace_all":true}]',
        )

        content = File.read(@test_file)

        assert_equal("bar bar bar\n", content)
        assert_includes(result, "Replaced 3 occurrence(s)")
      end

      def test_multi_edit_stops_on_error
        File.write(@test_file, "Hello World\n")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          edits_json: '[{"old_string":"Hello","new_string":"Hi"},{"old_string":"NonExistent","new_string":"Something"},{"old_string":"World","new_string":"Earth"}]',
        )

        # File should NOT be modified since an edit failed
        content = File.read(@test_file)

        assert_equal("Hello World\n", content) # Original content

        assert_includes(result, "Error")
        assert_includes(result, "old_string not found")
        assert_includes(result, "file has NOT been modified")
      end

      def test_multi_edit_file_not_found
        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: "/nonexistent/file.txt",
          edits_json: '[{"old_string":"test","new_string":"result"}]',
        )

        assert_includes(result, "Error")
        assert_includes(result, "File does not exist")
      end

      def test_multi_edit_empty_edits_array
        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          edits_json: "[]",
        )

        assert_includes(result, "Error")
        assert_includes(result, "edits array cannot be empty")
      end

      def test_multi_edit_validates_edit_structure
        File.write(@test_file, "test")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)

        # Missing new_string
        result = tool.execute(
          file_path: @test_file,
          edits_json: '[{"old_string":"test"}]',
        )

        assert_includes(result, "missing required field 'new_string'")

        # Missing old_string
        result = tool.execute(
          file_path: @test_file,
          edits_json: '[{"new_string":"result"}]',
        )

        assert_includes(result, "missing required field 'old_string'")
      end

      def test_multi_edit_same_old_and_new_strings
        File.write(@test_file, "test")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          edits_json: '[{"old_string":"test","new_string":"test"}]',
        )

        assert_includes(result, "Error")
        assert_includes(result, "must be different")
      end

      def test_multi_edit_multiple_occurrences_error
        File.write(@test_file, "foo foo foo\n")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(
          file_path: @test_file,
          edits_json: '[{"old_string":"foo","new_string":"bar"}]',
        )

        assert_includes(result, "Error")
        assert_includes(result, "Found 3 occurrences")
        assert_includes(result, "file has NOT been modified")
      end

      def test_multi_edit_with_nil_file_path
        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: nil, edits_json: "[]")

        assert_includes(result, "Error: file_path is required")
      end

      def test_multi_edit_with_blank_file_path
        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: "   ", edits_json: "[]")

        assert_includes(result, "Error: file_path is required")
      end

      def test_multi_edit_with_empty_file_path
        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: "", edits_json: "[]")

        assert_includes(result, "Error: file_path is required")
      end

      def test_multi_edit_with_nil_edits_json
        File.write(@test_file, "test")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: @test_file, edits_json: nil)

        # Nil causes TypeError, not JSON parse error
        assert_includes(result, "Error")
      end

      def test_multi_edit_with_invalid_json_syntax
        File.write(@test_file, "test")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: @test_file, edits_json: "{not valid json")

        assert_includes(result, "Error")
        assert_includes(result, "Invalid JSON")
      end

      def test_multi_edit_with_non_array_json
        File.write(@test_file, "test")

        # Read first
        Read.new(agent_name: :test_agent, directory: @temp_dir).execute(file_path: @test_file)

        tool = MultiEdit.new(agent_name: :test_agent, directory: @temp_dir)
        result = tool.execute(file_path: @test_file, edits_json: '{"key":"value"}')

        assert_includes(result, "Error")
        assert_includes(result, "edits must be an array")
      end
    end
  end
end
