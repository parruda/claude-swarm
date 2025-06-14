# frozen_string_literal: true

require "test_helper"
require "claude_swarm/cli"
require "tmpdir"
require "fileutils"

class TailCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@tmpdir)
    @cli = ClaudeSwarm::CLI.new
    
    # Save original environment
    @original_env = ENV["CLAUDE_SWARM_HOME"]
    # Set swarm home to temp directory for testing
    ENV["CLAUDE_SWARM_HOME"] = @tmpdir
    
    # Create test session directories
    @sessions_dir = File.join(@tmpdir, "sessions")
    FileUtils.mkdir_p(@sessions_dir)
    
    # Create test project directories
    @project_dir = File.join(@sessions_dir, "test+project")
    FileUtils.mkdir_p(@project_dir)
    
    # Create test sessions with timestamps
    @old_session = File.join(@project_dir, "20220101_120000")
    @new_session = File.join(@project_dir, "20220202_120000")
    FileUtils.mkdir_p(@old_session)
    FileUtils.mkdir_p(@new_session)
    
    # Create required files
    File.write(File.join(@old_session, "config.yml"), "test config")
    File.write(File.join(@new_session, "config.yml"), "test config")
    File.write(File.join(@old_session, "main.mcp.json"), "{}")
    File.write(File.join(@new_session, "main.mcp.json"), "{}")
    File.write(File.join(@old_session, "session.log"), "old session log")
    File.write(File.join(@new_session, "session.log"), "new session log")
    
    # Set creation times to ensure proper ordering
    FileUtils.touch(@old_session, mtime: Time.new(2022, 1, 1, 12, 0, 0))
    FileUtils.touch(@new_session, mtime: Time.new(2022, 2, 2, 12, 0, 0))
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
    # Restore original environment
    if @original_env
      ENV["CLAUDE_SWARM_HOME"] = @original_env
    else
      ENV.delete("CLAUDE_SWARM_HOME")
    end
  end
  
  def test_find_most_recent_session
    # Test that the most recent session is found
    most_recent = ClaudeSwarm::SessionPath.find_most_recent
    assert_equal @new_session, most_recent
  end
  
  def test_find_session_by_id
    # Test finding a session by ID
    session_id = File.basename(@old_session)
    found_session = ClaudeSwarm::SessionPath.find_by_id(session_id)
    assert_equal @old_session, found_session
  end
  
  def test_tail_with_session_id
    session_id = File.basename(@old_session)
    @cli.options = { lines: 10 }
    
    # Use capture_exec to test that exec is called with the right arguments
    exec_args = nil
    @cli.stub :exec, ->(cmd, *args) { exec_args = [cmd, *args] } do
      @cli.tail(session_id)
    end
    
    assert_equal ["tail", "-f", "-n", "10", File.join(@old_session, "session.log")], exec_args
  end
  
  def test_tail_with_most_recent_session
    @cli.options = { lines: 5 }
    
    # Use capture_exec to test that exec is called with the right arguments
    exec_args = nil
    @cli.stub :exec, ->(cmd, *args) { exec_args = [cmd, *args] } do
      @cli.tail
    end
    
    assert_equal ["tail", "-f", "-n", "5", File.join(@new_session, "session.log")], exec_args
  end
  
  def test_tail_with_nonexistent_session
    out, = capture_io do
      assert_raises(SystemExit) do
        @cli.tail("nonexistent")
      end
    end
    
    assert_match(/Session not found/, out)
  end
  
  def test_tail_with_no_log_file
    # Create a session without a log file
    no_log_session = File.join(@project_dir, "no_log")
    FileUtils.mkdir_p(no_log_session)
    File.write(File.join(no_log_session, "config.yml"), "test config")
    File.write(File.join(no_log_session, "main.mcp.json"), "{}")
    
    out, = capture_io do
      assert_raises(SystemExit) do
        @cli.stub :exec, -> { nil } do
          @cli.tail("no_log")
        end
      end
    end
    
    assert_match(/Log file not found/, out)
  end
end