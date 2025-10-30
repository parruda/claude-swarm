# frozen_string_literal: true

require "test_helper"

class OrchestratorWorktreeCleanupTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir
    @repo_dir = File.join(@test_dir, "test-repo")
    setup_git_repo(@repo_dir)

    @config_file = File.join(@repo_dir, "claude-swarm.yml")
    File.write(@config_file, swarm_config)

    @config = ClaudeSwarm::Configuration.new(@config_file, base_dir: @repo_dir)
    @generator = ClaudeSwarm::McpGenerator.new(@config)
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
    # Clean up any external worktrees created during tests
    FileUtils.rm_rf(ClaudeSwarm.joined_worktrees_dir("default"))
  end

  def test_orchestrator_skips_cleanup_with_uncommitted_changes
    orchestrator = ClaudeSwarm::Orchestrator.new(
      @config,
      @generator,
      worktree: "test-uncommitted",
    )

    # We need to run start first to get the session ID
    worktree_path = nil

    # Use a flag to track when to make changes
    changes_made = false

    # Mock system to simulate Claude execution and make changes
    orchestrator.stub(:system_with_pid!, lambda { |*args, chdir:, &block|
      block&.call(12345)
      # When claude is launched, we're in the worktree directory
      if args.any? { |arg| arg.to_s.include?("claude") } && !changes_made
        # Get the worktree path from the manager
        worktree_manager = orchestrator.instance_variable_get(:@worktree_manager)
        worktree_path = worktree_manager.created_worktrees.values.first if worktree_manager

        # Make uncommitted changes in the worktree directory using the provided chdir
        File.write(File.join(chdir, "uncommitted.txt"), "changes")
        changes_made = true
      end
      true
    }) do
      output = capture_io { orchestrator.start }.join

      # Check that cleanup warning was shown
      assert_match(/has uncommitted changes, skipping cleanup/, output)
    end

    # Verify worktree still exists
    assert(worktree_path, "Worktree path should be set")
    assert_path_exists(worktree_path, "Worktree should not be deleted with uncommitted changes")
  end

  def test_orchestrator_skips_cleanup_with_unpushed_commits
    orchestrator = ClaudeSwarm::Orchestrator.new(
      @config,
      @generator,
      worktree: "test-unpushed",
    )

    # We need to run start first to get the session ID
    worktree_path = nil

    # Use a flag to track when to make commits
    commits_made = false

    # Mock system to simulate Claude execution and make commits
    orchestrator.stub(:system_with_pid!, lambda { |*args, chdir:, &block|
      block&.call(12345)
      # When claude is launched, we're in the worktree directory
      if args.any? { |arg| arg.to_s.include?("claude") } && !commits_made
        # Get the worktree path from the manager
        worktree_manager = orchestrator.instance_variable_get(:@worktree_manager)
        worktree_path = worktree_manager.created_worktrees.values.first if worktree_manager

        # Make a commit in the worktree directory
        File.write(File.join(chdir, "new_feature.txt"), "feature content")
        # Run git commands with chdir option
        system("git", "add", ".", chdir: chdir, out: File::NULL, err: File::NULL)
        system("git", "commit", "-m", "New feature", chdir: chdir, out: File::NULL, err: File::NULL)
        commits_made = true
      end
      true
    }) do
      output = capture_io { orchestrator.start }.join

      # Check that cleanup warning was shown
      assert_match(/has unpushed commits, skipping cleanup/, output)
    end

    # Verify worktree still exists
    assert(worktree_path, "Worktree path should be set")
    assert_path_exists(worktree_path, "Worktree should not be deleted with unpushed commits")
  end

  def test_orchestrator_cleans_up_clean_worktree
    orchestrator = ClaudeSwarm::Orchestrator.new(
      @config,
      @generator,
      worktree: "test-clean",
    )

    # We'll get the worktree path after it's created
    worktree_path = nil

    orchestrator.stub(:system_with_pid!, lambda { |*args, **_kwargs, &block|
      block&.call(12345)
      # Get the worktree path from the manager when claude is launched
      if args.any? { |arg| arg.to_s.include?("claude") }
        worktree_manager = orchestrator.instance_variable_get(:@worktree_manager)
        worktree_path = worktree_manager.created_worktrees.values.first if worktree_manager
      end
      true
    }) do
      output = capture_io { orchestrator.start }.join

      # Should see normal cleanup message
      assert_match(/Removing worktree:.*test-clean/, output)
    end

    # Verify worktree was removed
    assert(worktree_path, "Worktree path should be set")
    refute_path_exists(worktree_path, "Clean worktree should be deleted")
  end

  private

  def setup_git_repo(dir)
    FileUtils.mkdir_p(dir)
    system_options = { out: File::NULL, err: File::NULL, chdir: dir }
    system("git", "init", "--quiet", **system_options)
    # Configure git user for GitHub Actions
    system("git", "config", "user.email", "test@example.com", **system_options)
    system("git", "config", "user.name", "Test User", **system_options)
    File.write(File.join(dir, "test.txt"), "test content")
    system("git", "add", ".", **system_options)
    system("git", "commit", "-m", "Initial commit", "--quiet", **system_options)
  end

  def swarm_config
    <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: main
        instances:
          main:
            description: "Main instance"
            directory: .
            model: sonnet
            allowed_tools: [Read]
    YAML
  end
end
