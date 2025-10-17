# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class McpServeOptionsTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "config.yml")
    File.write(@config_path, <<~YAML)
      version: 2
      swarm:
        name: "Test"
        lead: agent1
        agents:
          agent1:
            model: gpt-4
            system_prompt: "test"
    YAML
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_parse_config_file_argument
    options = SwarmCLI::McpServeOptions.new
    options.parse([@config_path])

    assert_equal(@config_path, options.config_file)
  end

  def test_config_file_accessor
    options = SwarmCLI::McpServeOptions.new
    options.parse([@config_path])

    assert_equal(@config_path, options.config_file)
  end

  def test_validate_success_for_existing_file
    options = SwarmCLI::McpServeOptions.new
    options.parse([@config_path])

    # Should not raise
    options.validate!
  end

  def test_validate_fails_for_missing_file
    options = SwarmCLI::McpServeOptions.new
    options.parse(["nonexistent.yml"])

    error = assert_raises(SwarmCLI::ExecutionError) do
      options.validate!
    end

    assert_match(/Configuration file not found/, error.message)
    assert_match(/nonexistent.yml/, error.message)
  end

  def test_validate_success_for_valid_path
    options = SwarmCLI::McpServeOptions.new
    options.parse([@config_path])

    # Should not raise any errors
    assert_silent do
      options.validate!
    end
  end
end
