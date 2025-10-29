# frozen_string_literal: true

require "test_helper"

class OrchestratorBeforeCommandsCreateDirectoryTest < Minitest::Test
  include TestHelpers

  def setup
    @original_dir = Dir.pwd
    @tmpdir = Dir.mktmpdir("claude_swarm_test")
    @config_path = File.join(@tmpdir, "claude-swarm.yml")

    # Set environment variables for test
    ENV["CLAUDE_SWARM_SESSION_PATH"] = File.join(@tmpdir, ".claude-swarm", "sessions", "test")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
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
          - mkdir -p ./project_workspace/evidence
          - mkdir -p ./project_workspace/reports
          - mkdir -p ./project_workspace/sessions
          - mkdir -p ./project_workspace/data
          - mkdir -p ./project_workspace/evidence/documents
          - mkdir -p ./project_workspace/evidence/archives
          - mkdir -p ./project_workspace/evidence/data
        instances:
          lead:
            description: "Lead developer"
            directory: ./project_workspace
            model: sonnet
    YAML

    # The project_workspace directory should NOT exist yet
    refute_path_exists(File.join(@tmpdir, "project_workspace"), "Directory should not exist before running")

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    # Mock system! to prevent actual Claude execution
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
      block&.call(12345)
      true
    }) do
      capture_io { orchestrator.start }
    end

    # Verify the directories were created
    assert_path_exists(File.join(@tmpdir, "project_workspace"))
    assert_path_exists(File.join(@tmpdir, "project_workspace", "evidence"))
    assert_path_exists(File.join(@tmpdir, "project_workspace", "reports"))
    assert_path_exists(File.join(@tmpdir, "project_workspace", "sessions"))
    assert_path_exists(File.join(@tmpdir, "project_workspace", "data"))
    assert_path_exists(File.join(@tmpdir, "project_workspace", "evidence", "documents"))
    assert_path_exists(File.join(@tmpdir, "project_workspace", "evidence", "archives"))
    assert_path_exists(File.join(@tmpdir, "project_workspace", "evidence", "data"))
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
    orchestrator.stub(:system_with_pid!, lambda { |*_args, **_kwargs, &block|
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
