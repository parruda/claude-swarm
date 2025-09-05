# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "yaml"

class ConfigurationBeforeCommandsTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir("claude_swarm_test")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_skips_directory_validation_when_before_commands_present
    # Create config with before commands and non-existent directory
    config_path = File.join(@temp_dir, "claude-swarm.yml")
    File.write(config_path, <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before:
          - mkdir -p ./frontend
        instances:
          lead:
            description: "Lead developer"
            directory: .
            model: sonnet
          frontend:
            description: "Frontend developer"
            directory: ./frontend
            model: sonnet
    YAML

    # Should not raise even though ./frontend doesn't exist yet
    # because before commands are present
    config = ClaudeSwarm::Configuration.new(config_path, base_dir: @temp_dir)

    # Verify the configuration loaded successfully
    assert_equal("Test Swarm", config.swarm_name)
    assert_equal("lead", config.main_instance)
    assert_equal(["mkdir -p ./frontend"], config.before_commands)

    # Directory doesn't exist yet
    refute(File.directory?(File.join(@temp_dir, "frontend")))

    # But validate_directories would fail if called explicitly
    assert_raises(ClaudeSwarm::Error) do
      config.validate_directories
    end

    # Create the directory (simulating what before_commands would do)
    FileUtils.mkdir_p(File.join(@temp_dir, "frontend"))

    # Now validate_directories should pass without raising
    config.validate_directories # Should not raise
  end

  def test_validates_directories_when_no_before_commands
    # Create config without before commands and non-existent directory
    config_path = File.join(@temp_dir, "claude-swarm.yml")
    File.write(config_path, <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            directory: .
            model: sonnet
          frontend:
            description: "Frontend developer"
            directory: ./frontend
            model: sonnet
    YAML

    # Should raise because ./frontend doesn't exist and no before commands
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(config_path, base_dir: @temp_dir)
    end
    assert_match(/Directory.*frontend.*does not exist/, error.message)
  end

  def test_validates_directories_with_empty_before_commands
    # Create config with empty before commands array and non-existent directory
    config_path = File.join(@temp_dir, "claude-swarm.yml")
    File.write(config_path, <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before: []
        instances:
          lead:
            description: "Lead developer"
            directory: .
            model: sonnet
          frontend:
            description: "Frontend developer"
            directory: ./frontend
            model: sonnet
    YAML

    # Should raise because before commands is empty
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(config_path, base_dir: @temp_dir)
    end
    assert_match(/Directory.*frontend.*does not exist/, error.message)
  end
end
