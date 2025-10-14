# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class OrchestratorBeforeCommandsCreateDirectoryTest < Minitest::Test
  include TestHelpers

  def setup
    @tmpdir = Dir.mktmpdir("claude_swarm_test")
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
    Dir.chdir(@tmpdir)

    # Set environment variables for test
    ENV["CLAUDE_SWARM_SESSION_PATH"] = File.join(@tmpdir, ".claude-swarm", "sessions", "test")
    ENV["CLAUDE_SWARM_ROOT_DIR"] = @tmpdir
  end

  def teardown
    Dir.chdir("/")
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
    ENV.delete("CLAUDE_SWARM_ROOT_DIR")
  end

  def test_before_commands_can_create_main_instance_directory
    # This mimics the user's scenario where before commands create the directory
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before:
          - echo "Creating directories..."
          - mkdir -p ./team_assessments/evidence
          - mkdir -p ./team_assessments/reports
          - mkdir -p ./team_assessments/sessions
          - mkdir -p ./team_assessments/data
          - mkdir -p ./team_assessments/evidence/vault
          - mkdir -p ./team_assessments/evidence/google
          - mkdir -p ./team_assessments/evidence/data
        instances:
          lead:
            description: "Lead developer"
            directory: ./team_assessments
            model: sonnet
    YAML

    # The team_assessments directory should NOT exist yet
    refute_path_exists(File.join(@tmpdir, "team_assessments"), "Directory should not exist before running")

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    # Mock system_with_pid! to prevent actual Claude execution
    orchestrator.stub(:system_with_pid!, lambda { |*_args, &block|
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Verify the directories were created
    assert_path_exists(File.join(@tmpdir, "team_assessments"))
    assert_path_exists(File.join(@tmpdir, "team_assessments", "evidence"))
    assert_path_exists(File.join(@tmpdir, "team_assessments", "reports"))
    assert_path_exists(File.join(@tmpdir, "team_assessments", "sessions"))
    assert_path_exists(File.join(@tmpdir, "team_assessments", "data"))
    assert_path_exists(File.join(@tmpdir, "team_assessments", "evidence", "vault"))
    assert_path_exists(File.join(@tmpdir, "team_assessments", "evidence", "google"))
    assert_path_exists(File.join(@tmpdir, "team_assessments", "evidence", "data"))
  end

  def test_before_commands_run_in_existing_directory_when_present
    # Test backward compatibility: if directory exists, before commands run in it
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before:
          - pwd > before_pwd.txt
          - touch marker.txt
        instances:
          lead:
            description: "Lead developer"
            directory: ./existing_dir
            model: sonnet
    YAML

    # Create the directory first
    existing_dir = File.join(@tmpdir, "existing_dir")
    FileUtils.mkdir_p(existing_dir)

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    # Mock system_with_pid! to prevent actual Claude execution
    orchestrator.stub(:system_with_pid!, lambda { |*_args, &block|
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Verify commands ran in the existing directory
    pwd_file = File.join(existing_dir, "before_pwd.txt")
    marker_file = File.join(existing_dir, "marker.txt")

    assert_path_exists(pwd_file, "PWD file should be in existing directory")
    assert_path_exists(marker_file, "Marker file should be in existing directory")

    # Verify the pwd matches the existing directory
    recorded_pwd = File.read(pwd_file).strip

    assert_equal(File.realpath(existing_dir), File.realpath(recorded_pwd))
  end

  private

  def write_config(content)
    File.write(@config_path, content)
  end
end
