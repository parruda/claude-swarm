# frozen_string_literal: true

require_relative "test_helper"

class SettingsGeneratorTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @temp_dir

    # Create a basic configuration with hooks
    @config = MockConfiguration.new(
      {
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
      {
        "test" => {
          name: "test",
          description: "Test instance",
          directory: ".",
          model: "sonnet",
          hooks: {},
        },
      },
    )

    generator = ClaudeSwarm::SettingsGenerator.new(config)
    generator.generate_all

    # No settings file should be created for empty hooks
    refute_path_exists(File.join(@temp_dir, "test_settings.json"))
  end

  def test_main_instance_gets_session_start_hook
    # Create config with main instance specified
    config = MockConfiguration.new(
      {
        "lead" => {
          name: "lead",
          description: "Lead developer",
          directory: ".",
          model: "opus",
        },
        "frontend" => {
          name: "frontend",
          description: "Frontend developer",
          directory: "./frontend",
          model: "sonnet",
        },
      },
      main_instance: "lead",
    )

    generator = ClaudeSwarm::SettingsGenerator.new(config)
    generator.generate_all

    # Check that main instance has SessionStart hook
    lead_settings = JSON.parse(File.read(File.join(@temp_dir, "lead_settings.json")))

    assert(lead_settings["hooks"])
    assert(lead_settings["hooks"]["SessionStart"])
    assert_equal(1, lead_settings["hooks"]["SessionStart"].size)

    session_start_hook = lead_settings["hooks"]["SessionStart"][0]

    assert_equal("startup", session_start_hook["matcher"])
    assert_equal(1, session_start_hook["hooks"].size)
    assert_equal("command", session_start_hook["hooks"][0]["type"])
    assert_match(/session_start_hook\.rb/, session_start_hook["hooks"][0]["command"])
    assert_equal(5, session_start_hook["hooks"][0]["timeout"])

    # Non-main instance should not have the automatic SessionStart hook
    refute_path_exists(File.join(@temp_dir, "frontend_settings.json"))
  end

  def test_main_instance_with_existing_hooks_merges_session_start
    # Create config with main instance that already has hooks
    config = MockConfiguration.new(
      {
        "lead" => {
          name: "lead",
          description: "Lead developer",
          directory: ".",
          model: "opus",
          hooks: {
            "PreToolUse" => [
              {
                "matcher" => "Write",
                "hooks" => [
                  {
                    "type" => "command",
                    "command" => "echo 'pre-write'",
                  },
                ],
              },
            ],
            "SessionStart" => [
              {
                "matcher" => "resume",
                "hooks" => [
                  {
                    "type" => "command",
                    "command" => "echo 'resuming'",
                  },
                ],
              },
            ],
          },
        },
      },
      main_instance: "lead",
    )

    generator = ClaudeSwarm::SettingsGenerator.new(config)
    generator.generate_all

    # Check that both hooks are present
    lead_settings = JSON.parse(File.read(File.join(@temp_dir, "lead_settings.json")))

    # PreToolUse should be preserved
    assert_equal(1, lead_settings["hooks"]["PreToolUse"].size)
    assert_equal("Write", lead_settings["hooks"]["PreToolUse"][0]["matcher"])

    # SessionStart should have both the existing and the new hook
    assert_equal(2, lead_settings["hooks"]["SessionStart"].size)

    # First should be the existing resume hook
    assert_equal("resume", lead_settings["hooks"]["SessionStart"][0]["matcher"])
    assert_equal("echo 'resuming'", lead_settings["hooks"]["SessionStart"][0]["hooks"][0]["command"])

    # Second should be our automatic startup hook
    assert_equal("startup", lead_settings["hooks"]["SessionStart"][1]["matcher"])
    assert_match(/session_start_hook\.rb/, lead_settings["hooks"]["SessionStart"][1]["hooks"][0]["command"])
  end

  # Mock configuration class for testing
  class MockConfiguration
    attr_reader :instances, :main_instance

    def initialize(instances, main_instance: "lead")
      @instances = instances
      @main_instance = main_instance
    end
  end
end
