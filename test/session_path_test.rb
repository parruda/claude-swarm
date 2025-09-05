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
      result = ClaudeSwarm::SessionPath.project_folder_name(tmpdir)
      # Extract just the last part of the path for comparison
      assert_includes(result, File.basename(tmpdir))
    end
  end

  def test_generate_session_path
    session_id = "550e8400-e29b-41d4-a716-446655440000"
    result = ClaudeSwarm::SessionPath.generate(
      working_dir: "/Users/paulo/test",
      session_id: session_id,
    )

    expected = ClaudeSwarm.joined_sessions_dir("Users+paulo+test", "550e8400-e29b-41d4-a716-446655440000")

    assert_equal(expected, result)
  end

  def test_generate_session_path_with_default_uuid
    result = ClaudeSwarm::SessionPath.generate(working_dir: "/Users/paulo/test")

    # Check that the path includes a UUID-formatted session ID
    assert_match(%r{sessions/Users\+paulo\+test/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$}, result)
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

    gitignore_path = ClaudeSwarm.joined_home_dir(".gitignore")

    assert_path_exists(gitignore_path)
    assert_equal("*\n", File.read(gitignore_path))
  end
end
