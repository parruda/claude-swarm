# frozen_string_literal: true

require "test_helper"

class SessionPathTest < Minitest::Test
  def test_project_folder_name_unix_path
    result = ClaudeSwarm::SessionPath.project_folder_name("/Users/paulo/src/claude-swarm")

    assert_equal("Users+paulo+src+claude-swarm", result)
  end

  def test_project_folder_name_windows_path
    # Test Windows-style path
    result = ClaudeSwarm::SessionPath.project_folder_name("C:\\Users\\paulo\\Documents\\project")

    assert_equal("C+Users+paulo+Documents+project", result)
  end

  def test_project_folder_name_with_current_directory
    # Should work with current directory
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        result = ClaudeSwarm::SessionPath.project_folder_name
        # Extract just the last part of the path for comparison
        assert(result.end_with?(File.basename(tmpdir)))
      end
    end
  end

  def test_generate_session_path
    timestamp = "20240101_120000"
    result = ClaudeSwarm::SessionPath.generate(
      working_dir: "/Users/paulo/test",
      timestamp: timestamp,
    )

    expected = File.join(ClaudeSwarm::SessionPath.swarm_home, "sessions/Users+paulo+test/20240101_120000")

    assert_equal(expected, result)
  end

  def test_from_env_with_path_set
    ENV["CLAUDE_SWARM_SESSION_PATH"] = "/custom/session/path"

    assert_equal("/custom/session/path", ClaudeSwarm::SessionPath.from_env)
  ensure
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def test_from_env_without_path_raises_error
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
    assert_raises(RuntimeError) { ClaudeSwarm::SessionPath.from_env }
  end

  def test_ensure_directory_creates_directories
    Dir.mktmpdir do |tmpdir|
      session_path = File.join(tmpdir, "test_sessions", "project", "timestamp")
      ClaudeSwarm::SessionPath.ensure_directory(session_path)

      assert(Dir.exist?(session_path))
    end
  end

  def test_ensure_directory_creates_gitignore
    # This will create .gitignore in the real ~/.claude-swarm directory
    # but that's okay for testing
    session_path = ClaudeSwarm::SessionPath.generate
    ClaudeSwarm::SessionPath.ensure_directory(session_path)

    gitignore_path = File.join(ClaudeSwarm::SessionPath.swarm_home, ".gitignore")

    assert_path_exists(gitignore_path)
    assert_equal("*\n", File.read(gitignore_path))
  end
end
