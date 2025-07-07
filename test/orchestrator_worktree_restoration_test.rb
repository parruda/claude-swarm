# frozen_string_literal: true

require "test_helper"
require_relative "../lib/claude_swarm/orchestrator"
require_relative "../lib/claude_swarm/configuration"
require_relative "../lib/claude_swarm/mcp_generator"
require "digest"
require "json"

class OrchestratorWorktreeRestorationTest < Minitest::Test
  def setup
    @test_dir = File.realpath(Dir.mktmpdir)
    @repo_dir = File.join(@test_dir, "test-repo")
    setup_git_repo(@repo_dir)

    @config_file = File.join(@repo_dir, "claude-swarm.yml")
    File.write(@config_file, swarm_config)

    @session_dir = Dir.mktmpdir
    @session_id = "20250618_123456"
    @session_path = File.join(@session_dir, @session_id)
    FileUtils.mkdir_p(@session_path)

    Dir.chdir(@repo_dir) do
      @config = ClaudeSwarm::Configuration.new(@config_file, base_dir: @repo_dir)
      @generator = ClaudeSwarm::McpGenerator.new(@config)
    end
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
    FileUtils.rm_rf(@session_dir)
    # Clean up any external worktrees
    FileUtils.rm_rf(File.expand_path("~/.claude-swarm/worktrees/20250618_123456"))
    FileUtils.rm_rf(File.expand_path("~/.claude-swarm/worktrees/default"))
  end

  def test_restoration_with_worktrees
    # First, create a session with worktrees
    worktree_name = "test-worktree-#{@session_id}"

    # Get external worktree path
    repo_name = File.basename(@repo_dir)
    repo_hash = Digest::SHA256.hexdigest(@repo_dir)[0..7]
    external_worktree_path = File.expand_path("~/.claude-swarm/worktrees/20250618_123456/#{repo_name}-#{repo_hash}/#{worktree_name}")

    # Simulate saving worktree metadata with external path
    metadata = {
      "start_directory" => @repo_dir,
      "timestamp" => Time.now.utc.iso8601,
      "swarm_name" => "Test Swarm",
      "claude_swarm_version" => "0.1.0",
      "worktree" => {
        "enabled" => true,
        "shared_name" => worktree_name,
        "created_paths" => {
          "#{@repo_dir}:#{worktree_name}" => external_worktree_path,
        },
        "instance_configs" => {
          "main" => { "skip" => false, "name" => worktree_name },
        },
      },
    }

    # Save metadata to session
    File.write(File.join(@session_path, "session_metadata.json"), JSON.pretty_generate(metadata))

    # Copy config to session
    FileUtils.cp(@config_file, File.join(@session_path, "config.yml"))

    # Create the worktree manually in external location (simulating previous session)
    FileUtils.mkdir_p(File.dirname(external_worktree_path))
    Dir.chdir(@repo_dir) do
      # Clean up any existing worktree with the same name
      system(
        "git",
        "worktree",
        "remove",
        "--force",
        external_worktree_path,
        out: File::NULL,
        err: File::NULL,
      )
      # Also try to remove any old internal worktree
      system(
        "git",
        "worktree",
        "remove",
        "--force",
        ".worktrees/#{worktree_name}",
        out: File::NULL,
        err: File::NULL,
      )
      # Delete the branch if it exists
      system(
        "git",
        "branch",
        "-D",
        worktree_name,
        out: File::NULL,
        err: File::NULL,
      )

      # Create new worktree
      system(
        "git",
        "worktree",
        "add",
        "-b",
        worktree_name,
        external_worktree_path,
        "HEAD",
        out: File::NULL,
        err: File::NULL,
      )
    end

    # Now test restoration
    Dir.chdir(@repo_dir) do
      orchestrator = ClaudeSwarm::Orchestrator.new(
        @config,
        @generator,
        restore_session_path: @session_path,
      )

      # Mock system call to verify directory
      worktree_dir_used = nil
      orchestrator.stub(:system, lambda { |*_args|
        worktree_dir_used = Dir.pwd
        true
      }) do
        capture_io { orchestrator.start }
      end

      # Verify the main instance started in the external worktree
      assert_equal(
        external_worktree_path,
        worktree_dir_used,
        "Main instance should start in the restored external worktree",
      )
    end
  end

  def test_restoration_without_worktrees
    # Simulate saving metadata without worktrees
    metadata = {
      "start_directory" => @repo_dir,
      "timestamp" => Time.now.utc.iso8601,
      "swarm_name" => "Test Swarm",
      "claude_swarm_version" => "0.1.0",
      # No worktree field
    }

    # Save metadata to session
    File.write(File.join(@session_path, "session_metadata.json"), JSON.pretty_generate(metadata))

    # Copy config to session
    FileUtils.cp(@config_file, File.join(@session_path, "config.yml"))

    # Test restoration
    Dir.chdir(@repo_dir) do
      orchestrator = ClaudeSwarm::Orchestrator.new(
        @config,
        @generator,
        restore_session_path: @session_path,
      )

      # Mock system call to verify directory
      dir_used = nil
      orchestrator.stub(:system, lambda { |*_args|
        dir_used = Dir.pwd
        true
      }) do
        capture_io { orchestrator.start }
      end

      # Verify the main instance started in the regular directory
      assert_equal(
        File.realpath(@repo_dir),
        File.realpath(dir_used),
        "Main instance should start in the regular directory when no worktrees were used",
      )
    end
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
