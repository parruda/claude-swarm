# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class OrchestratorWorktreeErrorCleanupTest < Minitest::Test
  include TestHelpers

  def setup
    @temp_dir = Dir.mktmpdir("claude_swarm_test")
    @repo_dir = File.join(@temp_dir, "test_repo")
    @config_file = File.join(@repo_dir, "claude-swarm.yml")

    # Initialize a git repo
    setup_git_repo(@repo_dir)

    # Create a simple configuration
    File.write(@config_file, <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before:
          - mkdir -p frontend
        instances:
          lead:
            description: "Lead developer"
            directory: .
            model: sonnet
          frontend:
            description: "Frontend developer"
            directory: ./frontend
            model: sonnet
            prompt: "You are a frontend developer"
    YAML

    # Change to repo directory
    Dir.chdir(@repo_dir)
  end

  def teardown
    Dir.chdir("/") # Change out of temp dir before deleting
    FileUtils.rm_rf(@temp_dir)
  end

  def test_cleans_up_worktrees_when_before_command_fails
    # Mock a failing before command
    File.write(@config_file, <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before:
          - exit 1
        instances:
          lead:
            description: "Lead developer"
            directory: .
            model: sonnet
    YAML

    config = ClaudeSwarm::Configuration.new(@config_file, base_dir: @repo_dir)
    generator = ClaudeSwarm::McpGenerator.new(config)

    # Create orchestrator with worktree option
    orchestrator = ClaudeSwarm::Orchestrator.new(
      config,
      generator,
      worktree: "test-branch",
    )

    # Mock the system! method to prevent actual Claude execution
    orchestrator.stub(:system!, nil) do
      orchestrator.stub(:stream_to_session_log, nil) do
        # Capture output to avoid test noise
        capture_io do
          # The orchestrator should exit(1) when before commands fail
          assert_raises(SystemExit) do
            orchestrator.start
          end
        end
      end
    end

    # Verify worktrees were cleaned up
    output, _status = Open3.capture2e("git", "-C", @repo_dir, "worktree", "list")
    # Should only have the main worktree, not the test-branch one
    assert_equal(1, output.lines.count, "Worktrees should be cleaned up after error")
  end

  def test_cleans_up_worktrees_when_directory_validation_fails
    # Create config with non-existent directory that before commands don't create
    File.write(@config_file, <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before:
          - echo "Not creating the required directory"
        instances:
          lead:
            description: "Lead developer"
            directory: .
            model: sonnet
          frontend:
            description: "Frontend developer"
            directory: ./frontend
            model: sonnet
            prompt: "You are a frontend developer"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_file, base_dir: @repo_dir)
    generator = ClaudeSwarm::McpGenerator.new(config)

    # Create orchestrator with worktree option
    orchestrator = ClaudeSwarm::Orchestrator.new(
      config,
      generator,
      worktree: "test-branch",
    )

    # Mock the system! method to prevent actual Claude execution
    orchestrator.stub(:system!, nil) do
      orchestrator.stub(:stream_to_session_log, nil) do
        # Capture output to avoid test noise
        capture_io do
          # The orchestrator should exit(1) when directory validation fails
          assert_raises(SystemExit) do
            orchestrator.start
          end
        end
      end
    end

    # Verify worktrees were cleaned up
    output, _status = Open3.capture2e("git", "-C", @repo_dir, "worktree", "list")
    # Should only have the main worktree
    assert_equal(1, output.lines.count, "Worktrees should be cleaned up after directory validation failure")
  end

  private

  def setup_git_repo(path)
    FileUtils.mkdir_p(path)
    Dir.chdir(path) do
      system("git init", out: File::NULL, err: File::NULL)
      system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
      system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
      File.write("README.md", "Test repo")
      system("git add README.md", out: File::NULL, err: File::NULL)
      system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)
    end
  end
end
