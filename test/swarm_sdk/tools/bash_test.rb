# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Tools
    class BashTest < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
      end

      def teardown
        FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
      end

      def test_bash_tool_executes_command
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "echo 'Hello'")

        assert_includes(result, "Exit code: 0")
        assert_includes(result, "Hello")
      end

      def test_bash_tool_captures_stderr
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "echo 'error' >&2")

        assert_includes(result, "STDERR:")
        assert_includes(result, "error")
      end

      def test_bash_tool_nonzero_exit_code
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "exit 1")

        assert_includes(result, "Exit code: 1")
        assert_includes(result, "<system-reminder>")
        assert_includes(result, "non-zero status")
      end

      def test_bash_tool_timeout
        tool = Bash.new(directory: @temp_dir)
        # Use a short timeout to test timeout behavior
        result = tool.execute(command: "sleep 10", timeout: 100) # 100ms

        assert_includes(result, "Error")
        assert_includes(result, "timed out")
      end

      def test_bash_tool_command_not_found
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "nonexistent_command_xyz")

        assert_includes(result, "Error")
      end

      def test_bash_tool_blocks_dangerous_commands
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "rm -rf /")

        assert_includes(result, "Error: Command blocked for safety reasons")
        assert_includes(result, "SECURITY BLOCK")
        assert_includes(result, "rm -rf /")
        refute_includes(result, "Exit code:") # Should not execute
      end

      def test_bash_tool_allows_safe_rm_commands
        tool = Bash.new(directory: @temp_dir)
        # This should not be blocked (specific path, not root)
        result = tool.execute(command: "rm -rf /tmp/test_dir")

        # Should execute normally (even if directory doesn't exist)
        assert_includes(result, "Exit code:")
        refute_includes(result, "SECURITY BLOCK")
      end

      def test_bash_tool_reminder_for_cat
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "cat /etc/hosts")

        assert_includes(result, "Exit code:")
        assert_includes(result, "Consider using the Read tool instead")
        assert_includes(result, "<system-reminder>")
      end

      def test_bash_tool_reminder_for_grep
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "grep pattern file.txt")

        assert_includes(result, "Exit code:")
        assert_includes(result, "Consider using the Grep tool instead")
        assert_includes(result, "<system-reminder>")
      end

      def test_bash_tool_reminder_for_find
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "find . -name '*.rb'")

        assert_includes(result, "Exit code:")
        assert_includes(result, "Consider using the Glob tool instead")
        assert_includes(result, "<system-reminder>")
      end

      def test_bash_tool_reminder_for_sed
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "sed 's/old/new/' file.txt")

        assert_includes(result, "Exit code:")
        assert_includes(result, "Consider using the Edit tool instead")
        assert_includes(result, "<system-reminder>")
      end

      def test_bash_tool_reminder_for_echo_redirection
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "echo 'test' > file.txt")

        assert_includes(result, "Exit code:")
        assert_includes(result, "Consider using the Write tool instead")
        assert_includes(result, "<system-reminder>")
      end

      def test_bash_tool_no_reminder_for_sed_with_pipe
        tool = Bash.new(directory: @temp_dir)
        # sed with pipe should not trigger reminder (it's a valid use case)
        result = tool.execute(command: "cat file.txt | sed 's/old/new/'")

        assert_includes(result, "Exit code:")
        refute_includes(result, "Consider using the Edit tool")
      end

      def test_bash_tool_no_reminder_for_normal_commands
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "ls -la")

        assert_includes(result, "Exit code:")
        refute_includes(result, "Consider using")
      end

      def test_bash_tool_with_description
        tool = Bash.new(directory: @temp_dir)
        result = tool.execute(command: "ls -la", description: "List all files")

        assert_includes(result, "Running: List all files")
        assert_includes(result, "$ ls -la")
      end

      def test_bash_tool_output_truncation
        tool = Bash.new(directory: @temp_dir)
        # Create a command that generates tons of output
        result = tool.execute(command: "ruby -e 'puts \"x\" * 35000'")

        assert_includes(result, "Output truncated")
        assert_operator(result.length, :<=, 31000) # 30000 + some extra for message
      end
    end
  end
end
