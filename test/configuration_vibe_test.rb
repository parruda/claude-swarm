# frozen_string_literal: true

require "test_helper"

class ConfigurationVibeTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_instance_with_vibe_true
    config_content = <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: leader
        instances:
          leader:
            description: "Main instance with vibe mode"
            vibe: true
          worker:
            description: "Worker without vibe"
            prompt: "You are a worker"
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)

    assert(config.instances["leader"][:vibe])
    refute(config.instances["worker"][:vibe])
  end

  def test_all_instances_default_vibe_false
    config_content = <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: leader
        instances:
          leader:
            description: "Main instance"
          worker:
            description: "Worker"
            prompt: "You are a worker"
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)

    refute(config.instances["leader"][:vibe])
    refute(config.instances["worker"][:vibe])
  end

  def test_mixed_vibe_settings
    config_content = <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: leader
        instances:
          leader:
            description: "Main instance"
            vibe: false
          worker1:
            description: "Worker with vibe"
            vibe: true
            prompt: "You are worker 1"
          worker2:
            description: "Worker without vibe setting"
            prompt: "You are worker 2"
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)

    refute(config.instances["leader"][:vibe])
    assert(config.instances["worker1"][:vibe])
    refute(config.instances["worker2"][:vibe])
  end
end
