# frozen_string_literal: true

require "test_helper"

module ClaudeSwarm
  class CLICommandsTest < Minitest::Test
    def setup
      @cli = CLI.new
      @run_dir = ClaudeSwarm.joined_run_dir
      @test_session_dir = ClaudeSwarm.joined_sessions_dir("test-project", "test-session-123")

      # Clean up any existing test data
      FileUtils.rm_rf(@run_dir)
      FileUtils.rm_rf(@test_session_dir)

      # Create test session directory structure
      FileUtils.mkdir_p(@test_session_dir)
      FileUtils.mkdir_p(@run_dir)
    end

    def teardown
      FileUtils.rm_rf(@run_dir)
      FileUtils.rm_rf(@test_session_dir)
    end

    def test_ps_command
      output = capture_io { @cli.ps }.first

      assert_equal("No active sessions\n", output)
    end

    def test_show_command_with_invalid_session
      assert_raises(SystemExit) do
        capture_io { @cli.show("non-existent") }
      end
    end

    def test_watch_command_with_invalid_session
      assert_raises(SystemExit) do
        capture_io { @cli.watch("non-existent") }
      end
    end

    def test_watch_command_with_valid_session
      # Create session with log file
      File.write(File.join(@test_session_dir, "session.log"), "test log content")
      File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

      # Mock exec to prevent actual tail execution
      @cli.stub(:exec, nil) do
        output = capture_io { @cli.watch("test-session-123") }
        # Exec was called, so there's no output
        assert_equal("", output.first)
      end
    end

    def test_clean_command_with_no_run_directory
      FileUtils.rm_rf(@run_dir)
      output = capture_io { @cli.clean }.first

      assert_match(/No cleanup needed/, output)
    end

    def test_clean_command_removes_stale_symlinks
      # Create a stale symlink
      File.symlink("/non/existent/path", File.join(@run_dir, "stale-session"))

      output = capture_io { @cli.clean }.first

      assert_match(/Cleaned 1 stale symlink/, output)

      # Verify symlink was removed
      refute_path_exists(File.join(@run_dir, "stale-session"))
    end

    def test_clean_command_with_days_option
      # Create an old symlink
      old_session_dir = ClaudeSwarm.joined_sessions_dir("test-project", "old-session")
      FileUtils.mkdir_p(old_session_dir)
      symlink_path = File.join(@run_dir, "old-session")
      File.symlink(old_session_dir, symlink_path)

      # Set mtime to 10 days ago
      ten_days_ago = Time.now - (10 * 86_400)
      File.utime(ten_days_ago, ten_days_ago, symlink_path)

      # Clean with 7 days threshold
      output = capture_io { @cli.invoke(:clean, [], days: 7) }.first

      assert_match(/Cleaned 1 stale symlink/, output)

      FileUtils.rm_rf(old_session_dir)
    end

    def test_clean_command_pluralization
      # Create multiple stale symlinks
      File.symlink("/non/existent/1", File.join(@run_dir, "stale-1"))
      File.symlink("/non/existent/2", File.join(@run_dir, "stale-2"))

      output = capture_io { @cli.clean }.first

      assert_match(/Cleaned 2 stale symlinks/, output)
    end

    def test_clean_command_skips_valid_symlinks
      # Create a valid symlink
      File.symlink(@test_session_dir, File.join(@run_dir, "valid-session"))

      output = capture_io { @cli.clean }.first

      assert_match(/No cleanup needed/, output)

      # Verify valid symlink still exists
      assert_path_exists(File.join(@run_dir, "valid-session"))
    end
  end
end
