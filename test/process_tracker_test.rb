# frozen_string_literal: true

require "test_helper"

class ProcessTrackerTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @tracker = ClaudeSwarm::ProcessTracker.new(@temp_dir)
    @pids_dir = File.join(@temp_dir, "pids")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_track_pid_creates_pid_file
    @tracker.track_pid(12_345, "test_process")

    pid_file = File.join(@pids_dir, "12345")

    assert_path_exists(pid_file, "PID file should be created")

    content = File.read(pid_file)

    assert_equal("test_process", content)
  end

  def test_track_multiple_pids
    @tracker.track_pid(12_345, "process_1")
    @tracker.track_pid(67_890, "process_2")

    pid_file1 = File.join(@pids_dir, "12345")
    pid_file2 = File.join(@pids_dir, "67890")

    assert_path_exists(pid_file1)
    assert_path_exists(pid_file2)

    assert_equal("process_1", File.read(pid_file1))
    assert_equal("process_2", File.read(pid_file2))
  end

  def test_cleanup_session_with_no_directory
    # Should not raise error when no pids directory exists
    ClaudeSwarm::ProcessTracker.cleanup_session(@temp_dir)
  end

  def test_cleanup_removes_pids_directory
    @tracker.track_pid(12_345, "test_process")

    assert_path_exists(@pids_dir)
    capture_io { @tracker.cleanup_all }

    refute_path_exists(@pids_dir, "pids directory should be removed after cleanup")
  end

  def test_cleanup_handles_nonexistent_processes
    # Track a PID that doesn't exist
    @tracker.track_pid(999_999_999, "nonexistent_process")

    # Should not raise error
    assert_output(/already terminated/) do
      @tracker.cleanup_all
    end
  end

  def test_creates_pids_directory_on_initialization
    assert_path_exists(@pids_dir, "pids directory should be created on initialization")
  end
end
