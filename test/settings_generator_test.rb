# frozen_string_literal: true

require_relative "test_helper"

class SettingsGeneratorTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @temp_dir

    # Create a basic configuration with hooks
    @config = MockConfiguration.new(
      "lead" => {
        name: "lead",
        description: "Lead developer",
        directory: ".",
        model: "opus",
        hooks: {
          "PreToolUse" => [
            {
              "matcher" => "Write|Edit",
              "hooks" => [
                {
                  "type" => "command",
                  "command" => "echo 'pre-write'",
                },
              ],
            },
          ],
        },
      },
      "frontend" => {
        name: "frontend",
        description: "Frontend developer",
        directory: "./frontend",
        model: "sonnet",
        hooks: {
          "PostToolUse" => [
            {
              "matcher" => "Bash",
              "hooks" => [
                {
                  "type" => "command",
                  "command" => "echo 'post-bash'",
                  "timeout" => 10,
                },
              ],
            },
          ],
        },
      },
      "backend" => {
        name: "backend",
        description: "Backend developer",
        directory: "./backend",
        model: "sonnet",
        # No hooks
      },
    )

    @generator = ClaudeSwarm::SettingsGenerator.new(@config)
  end

  def teardown
    FileUtils.remove_entry(@temp_dir) if Dir.exist?(@temp_dir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def test_generate_all_creates_settings_files_with_hooks
    @generator.generate_all

    # Check that settings files were created for instances with hooks
    assert_path_exists(File.join(@temp_dir, "lead_settings.json"))
    assert_path_exists(File.join(@temp_dir, "frontend_settings.json"))

    # No settings file should be created for instances without hooks
    refute_path_exists(File.join(@temp_dir, "backend_settings.json"))
  end

  def test_settings_content_matches_hooks_configuration
    @generator.generate_all

    # Check lead settings
    lead_settings = JSON.parse(File.read(File.join(@temp_dir, "lead_settings.json")))

    assert_equal(1, lead_settings["hooks"]["PreToolUse"].size)
    assert_equal("Write|Edit", lead_settings["hooks"]["PreToolUse"][0]["matcher"])
    assert_equal("echo 'pre-write'", lead_settings["hooks"]["PreToolUse"][0]["hooks"][0]["command"])

    # Check frontend settings
    frontend_settings = JSON.parse(File.read(File.join(@temp_dir, "frontend_settings.json")))

    assert_equal(1, frontend_settings["hooks"]["PostToolUse"].size)
    assert_equal("Bash", frontend_settings["hooks"]["PostToolUse"][0]["matcher"])
    assert_equal("echo 'post-bash'", frontend_settings["hooks"]["PostToolUse"][0]["hooks"][0]["command"])
    assert_equal(10, frontend_settings["hooks"]["PostToolUse"][0]["hooks"][0]["timeout"])
  end

  def test_settings_path_returns_correct_path
    assert_equal(File.join(@temp_dir, "lead_settings.json"), @generator.settings_path("lead"))
    assert_equal(File.join(@temp_dir, "frontend_settings.json"), @generator.settings_path("frontend"))
  end

  def test_empty_hooks_configuration
    config = MockConfiguration.new(
      "test" => {
        name: "test",
        description: "Test instance",
        directory: ".",
        model: "sonnet",
        hooks: {},
      },
    )

    generator = ClaudeSwarm::SettingsGenerator.new(config)
    generator.generate_all

    # No settings file should be created for empty hooks
    refute_path_exists(File.join(@temp_dir, "test_settings.json"))
  end

  # Mock configuration class for testing
  class MockConfiguration
    attr_reader :instances

    def initialize(instances)
      @instances = instances
    end
  end
end
