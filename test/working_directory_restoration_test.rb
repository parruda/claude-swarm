# frozen_string_literal: true

require "test_helper"

class WorkingDirectoryRestorationTest < Minitest::Test
  def setup
    # Create a directory structure to test path resolution
    @root_dir = Dir.mktmpdir
    @project_dir = File.join(@root_dir, "my_project")
    @subdir = File.join(@project_dir, "subdir")
    @session_dir = File.join(@root_dir, "sessions", "my_project", "20240101_120000")

    FileUtils.mkdir_p(@project_dir)
    FileUtils.mkdir_p(@subdir)
    FileUtils.mkdir_p(@session_dir)

    # Create config file in project directory
    @config_path = File.join(@project_dir, "claude-swarm.yml")
    File.write(@config_path, <<~YAML)
      version: 1
      swarm:
        name: "Path Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            directory: .
            model: sonnet
            connections: [worker]
          worker:
            description: "Worker in subdirectory"
            directory: ./subdir
            model: sonnet
    YAML

    # Copy config to session directory (simulating what happens during initial run)
    FileUtils.cp(@config_path, File.join(@session_dir, "config.yml"))

    # Save the original working directory
    File.write(File.join(@session_dir, "root_directory"), @project_dir)
  end

  def teardown
    FileUtils.rm_rf(@root_dir)
  end

  def test_directory_resolution_during_restoration
    # Test that config loading uses base_dir when provided,
    # and config file's directory when base_dir is not provided

    # Load config without base_dir (uses config file's directory as base)
    config_normal = ClaudeSwarm::Configuration.new(@config_path)

    # Load config with explicit base_dir (as done during restoration)
    config_restored = ClaudeSwarm::Configuration.new(
      File.join(@session_dir, "config.yml"),
      base_dir: @project_dir,
    )

    # Both should resolve directories correctly
    lead_normal = config_normal.instances["lead"]
    lead_restored = config_restored.instances["lead"]

    assert_equal(
      File.realpath(@project_dir),
      File.realpath(lead_normal[:directory]),
      "Normal load should resolve . relative to config file location",
    )
    assert_equal(
      File.realpath(@project_dir),
      File.realpath(lead_restored[:directory]),
      "Restored load with base_dir should resolve . to project directory",
    )

    worker_normal = config_normal.instances["worker"]
    worker_restored = config_restored.instances["worker"]

    assert_equal(
      File.realpath(@subdir),
      File.realpath(worker_normal[:directory]),
      "Normal load should resolve ./subdir relative to config file location",
    )
    assert_equal(
      File.realpath(@subdir),
      File.realpath(worker_restored[:directory]),
      "Restored load should resolve ./subdir relative to base_dir",
    )
  end

  def test_restoration_from_different_working_directory
    # Test that restoration works by using base_dir parameter,
    # regardless of current working directory

    # This simulates what happens in CLI#restore_session
    original_dir = File.read(File.join(@session_dir, "root_directory")).strip

    # Load configuration with original directory as base
    # This works from any directory without needing to chdir
    config = ClaudeSwarm::Configuration.new(
      File.join(@session_dir, "config.yml"),
      base_dir: original_dir,
    )

    # Verify instances have correct directories (normalize paths for comparison)
    assert_equal(File.realpath(@project_dir), File.realpath(config.instances["lead"][:directory]))
    assert_equal(File.realpath(@subdir), File.realpath(config.instances["worker"][:directory]))
  end
end
