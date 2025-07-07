# frozen_string_literal: true

require "test_helper"

class WorktreeManagerTest < Minitest::Test
  def setup
    @test_dir = File.realpath(Dir.mktmpdir)
    @repo_dir = File.join(@test_dir, "test-repo")
    @other_repo_dir = File.join(@test_dir, "other-repo")

    # Create test Git repositories
    setup_git_repo(@repo_dir)
    setup_git_repo(@other_repo_dir)

    # Suppress output during tests
    @original_prompt = ENV["CLAUDE_SWARM_PROMPT"]
    ENV["CLAUDE_SWARM_PROMPT"] = "true"
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
    # Restore original environment
    if @original_prompt
      ENV["CLAUDE_SWARM_PROMPT"] = @original_prompt
    else
      ENV.delete("CLAUDE_SWARM_PROMPT")
    end
  end

  def test_initialize_with_custom_name
    manager = ClaudeSwarm::WorktreeManager.new("feature-x")

    assert_equal("feature-x", manager.worktree_name)
  end

  def test_initialize_with_auto_generated_name
    manager = ClaudeSwarm::WorktreeManager.new

    assert_match(/^worktree-[a-z0-9]{5}$/, manager.worktree_name)
  end

  def test_setup_worktrees_single_repo
    manager = ClaudeSwarm::WorktreeManager.new("test-worktree")

    instances = [
      { name: "main", directory: @repo_dir },
      { name: "sub", directory: File.join(@repo_dir, "subdir") },
    ]

    manager.setup_worktrees(instances)

    # Check worktree was created in external directory
    repo_name = File.basename(@repo_dir)
    repo_hash = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    worktree_path = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name}-#{repo_hash}/test-worktree")

    assert_path_exists(worktree_path, "Worktree should be created in external directory")

    # Check instances were updated
    assert_equal(worktree_path, instances[0][:directory])
    assert_equal(File.join(worktree_path, "subdir"), instances[1][:directory])

    # Check that worktree is on a branch, not detached HEAD
    Dir.chdir(worktree_path) do
      output = %x(git rev-parse --abbrev-ref HEAD).strip

      assert_equal("test-worktree", output, "Worktree should be on a branch named 'test-worktree'")
    end
  end

  def test_setup_worktrees_multiple_repos
    manager = ClaudeSwarm::WorktreeManager.new("multi-repo")

    instances = [
      { name: "main", directory: @repo_dir },
      { name: "other", directory: @other_repo_dir },
    ]

    manager.setup_worktrees(instances)

    # Check both worktrees were created in external directories
    repo_name1 = File.basename(@repo_dir)
    repo_hash1 = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    worktree_path1 = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name1}-#{repo_hash1}/multi-repo")

    repo_name2 = File.basename(@other_repo_dir)
    repo_hash2 = Digest::SHA256.hexdigest(@other_repo_dir)[0..7]
    worktree_path2 = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name2}-#{repo_hash2}/multi-repo")

    assert_path_exists(worktree_path1, "First worktree should be created")
    assert_path_exists(worktree_path2, "Second worktree should be created")

    # Check instances were updated
    assert_equal(worktree_path1, instances[0][:directory])
    assert_equal(worktree_path2, instances[1][:directory])
  end

  def test_setup_worktrees_with_directories_array
    manager = ClaudeSwarm::WorktreeManager.new("array-test")

    instances = [
      {
        name: "multi",
        directories: [@repo_dir, File.join(@repo_dir, "subdir"), @other_repo_dir],
      },
    ]

    manager.setup_worktrees(instances)

    # Check all directories were mapped
    repo_name1 = File.basename(@repo_dir)
    repo_hash1 = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    worktree_path1 = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name1}-#{repo_hash1}/array-test")

    repo_name2 = File.basename(@other_repo_dir)
    repo_hash2 = Digest::SHA256.hexdigest(@other_repo_dir)[0..7]
    worktree_path2 = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name2}-#{repo_hash2}/array-test")

    expected_dirs = [
      worktree_path1,
      File.join(worktree_path1, "subdir"),
      worktree_path2,
    ]

    assert_equal(expected_dirs, instances[0][:directories])
  end

  def test_map_to_worktree_path_non_git_directory
    manager = ClaudeSwarm::WorktreeManager.new("test")
    non_git_dir = File.join(@test_dir, "non-git")
    FileUtils.mkdir_p(non_git_dir)

    # Should return original path for non-git directories
    assert_equal(non_git_dir, manager.map_to_worktree_path(non_git_dir, "test"))
  end

  def test_cleanup_worktrees
    manager = ClaudeSwarm::WorktreeManager.new("cleanup-test")

    instances = [
      { name: "main", directory: @repo_dir },
      { name: "other", directory: @other_repo_dir },
    ]

    manager.setup_worktrees(instances)

    # Verify worktrees exist
    repo_name1 = File.basename(@repo_dir)
    repo_hash1 = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    worktree_path1 = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name1}-#{repo_hash1}/cleanup-test")

    repo_name2 = File.basename(@other_repo_dir)
    repo_hash2 = Digest::SHA256.hexdigest(@other_repo_dir)[0..7]
    worktree_path2 = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name2}-#{repo_hash2}/cleanup-test")

    assert_path_exists(worktree_path1)
    assert_path_exists(worktree_path2)

    # Clean up
    manager.cleanup_worktrees

    # Verify worktrees are removed
    refute_path_exists(worktree_path1, "First worktree should be removed")
    refute_path_exists(worktree_path2, "Second worktree should be removed")
  end

  def test_session_metadata
    manager = ClaudeSwarm::WorktreeManager.new("metadata-test")

    instances = [
      { name: "main", directory: @repo_dir },
    ]

    manager.setup_worktrees(instances)

    metadata = manager.session_metadata

    assert(metadata[:enabled])
    assert_equal("metadata-test", metadata[:shared_name])
    assert_kind_of(Hash, metadata[:created_paths])

    repo_name = File.basename(@repo_dir)
    repo_hash = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    expected_path = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name}-#{repo_hash}/metadata-test")

    assert_equal(expected_path, metadata[:created_paths]["#{@repo_dir}:metadata-test"])
  end

  def test_existing_worktree_reuse
    # Create a worktree manually in external location
    worktree_name = "existing-worktree"
    repo_name = File.basename(@repo_dir)
    repo_hash = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    worktree_base = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name}-#{repo_hash}")
    FileUtils.mkdir_p(worktree_base)
    worktree_path = File.join(worktree_base, worktree_name)

    Dir.chdir(@repo_dir) do
      system("git", "worktree", "add", "-b", worktree_name, worktree_path, "HEAD", out: File::NULL, err: File::NULL)
    end

    manager = ClaudeSwarm::WorktreeManager.new(worktree_name)

    instances = [
      { name: "main", directory: @repo_dir },
    ]

    # Should reuse existing worktree without error
    manager.setup_worktrees(instances)

    assert_equal(worktree_path, instances[0][:directory])
  end

  def test_existing_branch_reuse
    # Create a branch first
    branch_name = "existing-branch"
    Dir.chdir(@repo_dir) do
      # Get current branch
      current_branch = %x(git rev-parse --abbrev-ref HEAD).strip

      # Create a new branch from current position
      system("git", "branch", branch_name, out: File::NULL, err: File::NULL)

      # Only checkout if we're not already on that branch
      if current_branch != branch_name
        # Stay on current branch - don't need to switch
      end
    end

    manager = ClaudeSwarm::WorktreeManager.new(branch_name)

    instances = [
      { name: "main", directory: @repo_dir },
    ]

    # Should create worktree using existing branch
    manager.setup_worktrees(instances)

    repo_name = File.basename(@repo_dir)
    repo_hash = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    worktree_path = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name}-#{repo_hash}/#{branch_name}")

    assert_path_exists(worktree_path, "Worktree should be created")

    # Check that worktree is on the existing branch
    Dir.chdir(worktree_path) do
      output = %x(git rev-parse --abbrev-ref HEAD).strip

      assert_equal(branch_name, output, "Worktree should be on the existing branch")
    end
  end

  def test_empty_worktree_name_generates_name
    manager = ClaudeSwarm::WorktreeManager.new("")

    assert_match(/^worktree-[a-z0-9]{5}$/, manager.worktree_name)
  end

  def test_default_thor_worktree_value_generates_name
    # When Thor gets --worktree without a value, it defaults to "worktree"
    manager = ClaudeSwarm::WorktreeManager.new("worktree")

    assert_match(/^worktree-[a-z0-9]{5}$/, manager.worktree_name)
  end

  def test_worktree_name_with_session_id
    # When session ID is provided, it should use it in the worktree name
    manager = ClaudeSwarm::WorktreeManager.new(nil, session_id: "20241206_143022")

    assert_equal("worktree-20241206_143022", manager.worktree_name)
  end

  def test_empty_string_with_session_id
    # When empty string is passed with session ID
    manager = ClaudeSwarm::WorktreeManager.new("", session_id: "20241206_143022")

    assert_equal("worktree-20241206_143022", manager.worktree_name)
  end

  def test_thor_default_with_session_id
    # When Thor default "worktree" is passed with session ID
    manager = ClaudeSwarm::WorktreeManager.new("worktree", session_id: "20241206_143022")

    assert_equal("worktree-20241206_143022", manager.worktree_name)
  end

  def test_gitignore_created_in_worktrees_directory
    # This test is no longer relevant since worktrees are now external
    # Skip this test
    skip("Gitignore test not applicable for external worktrees")
  end

  def test_per_instance_worktree_false
    manager = ClaudeSwarm::WorktreeManager.new("shared-worktree")

    instances = [
      { name: "main", directory: @repo_dir, worktree: true },
      { name: "other", directory: @other_repo_dir, worktree: false },
    ]

    manager.setup_worktrees(instances)

    # Main instance should be in worktree
    repo_name = File.basename(@repo_dir)
    repo_hash = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    expected_path = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name}-#{repo_hash}/shared-worktree")

    assert_equal(expected_path, instances[0][:directory])

    # Other instance should keep original directory
    assert_equal(@other_repo_dir, instances[1][:directory])
  end

  def test_per_instance_custom_worktree_name
    manager = ClaudeSwarm::WorktreeManager.new("shared-worktree")

    instances = [
      { name: "main", directory: @repo_dir, worktree: true },
      { name: "other", directory: @other_repo_dir, worktree: "custom-branch" },
    ]

    manager.setup_worktrees(instances)

    # Main instance should use shared worktree
    repo_name1 = File.basename(@repo_dir)
    repo_hash1 = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    expected_path1 = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name1}-#{repo_hash1}/shared-worktree")

    assert_equal(expected_path1, instances[0][:directory])

    # Other instance should use custom worktree
    repo_name2 = File.basename(@other_repo_dir)
    repo_hash2 = Digest::SHA256.hexdigest(@other_repo_dir)[0..7]
    expected_path2 = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name2}-#{repo_hash2}/custom-branch")

    assert_equal(expected_path2, instances[1][:directory])
  end

  def test_per_instance_worktree_without_cli_option
    manager = ClaudeSwarm::WorktreeManager.new(nil)

    instances = [
      { name: "main", directory: @repo_dir }, # No worktree config, should not use worktree
      { name: "other", directory: @other_repo_dir, worktree: "feature-x" },
    ]

    manager.setup_worktrees(instances)

    # Main instance should keep original directory (no CLI option, no instance config)
    assert_equal(@repo_dir, instances[0][:directory])

    # Other instance should use custom worktree
    repo_name = File.basename(@other_repo_dir)
    repo_hash = Digest::SHA256.hexdigest(@other_repo_dir)[0..7]
    expected_path = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name}-#{repo_hash}/feature-x")

    assert_equal(expected_path, instances[1][:directory])
  end

  def test_per_instance_worktree_true_without_cli_generates_name
    manager = ClaudeSwarm::WorktreeManager.new(nil)

    instances = [
      { name: "main", directory: @repo_dir, worktree: true },
    ]

    manager.setup_worktrees(instances)

    # Should generate a worktree with auto-generated name
    assert_match(%r{/worktree-[a-z0-9]{5}$}, instances[0][:directory])
  end

  def test_cleanup_skips_worktree_with_uncommitted_changes
    manager = ClaudeSwarm::WorktreeManager.new("test-changes")

    instances = [
      { name: "main", directory: @repo_dir },
    ]

    manager.setup_worktrees(instances)

    # Make changes in the worktree
    repo_name = File.basename(@repo_dir)
    repo_hash = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    worktree_path = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name}-#{repo_hash}/test-changes")

    assert_path_exists(worktree_path)

    File.write(File.join(worktree_path, "new_file.txt"), "uncommitted content")

    # Temporarily unset the prompt suppression for this test
    ENV.delete("CLAUDE_SWARM_PROMPT")

    # Capture output during cleanup
    output = capture_io { manager.cleanup_worktrees }.join

    # Restore the prompt suppression
    ENV["CLAUDE_SWARM_PROMPT"] = "true"

    # Verify worktree was NOT removed
    assert_path_exists(worktree_path, "Worktree with uncommitted changes should not be removed")
    assert_match(/has uncommitted changes, skipping cleanup/, output)
  end

  def test_cleanup_skips_worktree_with_unpushed_commits
    manager = ClaudeSwarm::WorktreeManager.new("test-unpushed")

    instances = [
      { name: "main", directory: @repo_dir },
    ]

    manager.setup_worktrees(instances)

    # Get the actual worktree path from the updated instance
    worktree_path = instances.first[:directory]

    assert_path_exists(worktree_path)

    Dir.chdir(worktree_path) do
      File.write("committed_file.txt", "committed content")
      system("git", "add", ".", out: File::NULL, err: File::NULL)
      system("git", "commit", "-m", "Unpushed commit", out: File::NULL, err: File::NULL)
    end

    # Temporarily unset the prompt suppression for this test
    ENV.delete("CLAUDE_SWARM_PROMPT")

    # Capture output during cleanup
    output = capture_io { manager.cleanup_worktrees }.join

    # Restore the prompt suppression
    ENV["CLAUDE_SWARM_PROMPT"] = "true"

    # Verify worktree was NOT removed
    assert_path_exists(worktree_path, "Worktree with unpushed commits should not be removed")
    assert_match(/has unpushed commits, skipping cleanup/, output)
  end

  def test_cleanup_removes_clean_worktree
    manager = ClaudeSwarm::WorktreeManager.new("test-clean")

    instances = [
      { name: "main", directory: @repo_dir },
    ]

    manager.setup_worktrees(instances)

    repo_name = File.basename(@repo_dir)
    repo_hash = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    worktree_path = File.expand_path("~/.claude-swarm/worktrees/default/#{repo_name}-#{repo_hash}/test-clean")

    assert_path_exists(worktree_path)

    # Cleanup should remove the clean worktree
    manager.cleanup_worktrees

    refute_path_exists(worktree_path, "Clean worktree should be removed")
  end

  def test_cleanup_external_directories_with_session_id
    manager = ClaudeSwarm::WorktreeManager.new("test-external", session_id: "test_session_123")

    instances = [
      { name: "main", directory: @repo_dir },
    ]

    manager.setup_worktrees(instances)

    # Check that session directory exists
    session_worktree_dir = File.expand_path("~/.claude-swarm/worktrees/test_session_123")

    assert_path_exists(session_worktree_dir)

    # Cleanup should remove the worktree and try to clean up empty directories
    manager.cleanup_worktrees

    # The session directory should be removed if empty
    refute_path_exists(session_worktree_dir, "Empty session worktree directory should be removed")
  end

  def test_cleanup_removes_worktree_created_from_feature_branch_without_changes
    # Create a feature branch in the main repo
    Dir.chdir(@repo_dir) do
      # Create and checkout a feature branch
      system("git", "checkout", "-b", "feature-branch", out: File::NULL, err: File::NULL)
      # Make a commit on the feature branch
      File.write("feature.txt", "feature content")
      system("git", "add", ".", out: File::NULL, err: File::NULL)
      system("git", "commit", "-m", "Feature commit", out: File::NULL, err: File::NULL)
    end

    manager = ClaudeSwarm::WorktreeManager.new("test-feature-worktree")

    instances = [
      { name: "main", directory: @repo_dir },
    ]

    manager.setup_worktrees(instances)

    # Get the actual worktree path from the updated instance
    worktree_path = instances.first[:directory]

    assert_path_exists(worktree_path)

    # Don't make any changes in the worktree - it should still be removable
    # Capture output during cleanup
    output = capture_io { manager.cleanup_worktrees }.join

    # The worktree should be removed because it has no changes
    refute_path_exists(worktree_path, "Worktree created from feature branch with no changes should be removed")
    refute_match(/has unpushed commits, skipping cleanup/, output)
  end

  private

  def setup_git_repo(dir)
    FileUtils.mkdir_p(dir)
    Dir.chdir(dir) do
      system("git", "init", "--quiet", out: File::NULL, err: File::NULL)
      # Configure git user for GitHub Actions
      system("git", "config", "user.email", "test@example.com", out: File::NULL, err: File::NULL)
      system("git", "config", "user.name", "Test User", out: File::NULL, err: File::NULL)
      File.write("test.txt", "test content")
      system("git", "add", ".", out: File::NULL, err: File::NULL)
      system("git", "commit", "-m", "Initial commit", "--quiet", out: File::NULL, err: File::NULL)
    end

    # Create subdirectory
    FileUtils.mkdir_p(File.join(dir, "subdir"))
  end
end
