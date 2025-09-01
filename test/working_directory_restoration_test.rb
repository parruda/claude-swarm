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
            prompt: "You are a worker instance"
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
    # Simulate restoration from a different directory
    Dir.chdir(@root_dir) do
      # Load config without base_dir (like it would during normal run)
      config_normal = ClaudeSwarm::Configuration.new(@config_path)

      # Load config with base_dir (like it would during restoration)
      config_restored = ClaudeSwarm::Configuration.new(
        File.join(@session_dir, "config.yml"),
        base_dir: @project_dir,
      )

      # Verify directories are resolved correctly
      lead_normal = config_normal.instances["lead"]
      lead_restored = config_restored.instances["lead"]

      assert_equal(
        File.realpath(@project_dir),
        File.realpath(lead_normal[:directory]),
        "Normal load should resolve . to project directory",
      )
      assert_equal(
        File.realpath(@project_dir),
        File.realpath(lead_restored[:directory]),
        "Restored load should also resolve . to project directory",
      )

      worker_normal = config_normal.instances["worker"]
      worker_restored = config_restored.instances["worker"]

      assert_equal(
        File.realpath(@subdir),
        File.realpath(worker_normal[:directory]),
        "Normal load should resolve ./subdir correctly",
      )
      assert_equal(
        File.realpath(@subdir),
        File.realpath(worker_restored[:directory]),
        "Restored load should also resolve ./subdir correctly",
      )
    end
  end

  def test_restoration_from_different_working_directory
    # Test that restoration works even when invoked from a completely different directory
    other_dir = Dir.mktmpdir

    begin
      Dir.chdir(other_dir) do
        # This simulates what happens in CLI#restore_session
        original_dir = File.read(File.join(@session_dir, "root_directory")).strip

        # Change to original directory
        Dir.chdir(original_dir) do
          # Load configuration with current directory as base
          config = ClaudeSwarm::Configuration.new(
            File.join(@session_dir, "config.yml"),
            base_dir: Dir.pwd,
          )

          # Verify instances have correct directories (normalize paths for comparison)
          assert_equal(File.realpath(@project_dir), File.realpath(config.instances["lead"][:directory]))
          assert_equal(File.realpath(@subdir), File.realpath(config.instances["worker"][:directory]))
        end
      end
    ensure
      FileUtils.rm_rf(other_dir)
    end
  end
end
