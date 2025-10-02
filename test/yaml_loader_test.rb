# frozen_string_literal: true

require "test_helper"

class YamlLoaderTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir("yaml_loader_test")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  def test_load_config_file_with_valid_yaml
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            directory: "."
    YAML

    config_file = File.join(@temp_dir, "config.yml")
    File.write(config_file, yaml_content)

    result = ClaudeSwarm::YamlLoader.load_config_file(config_file)

    assert_equal(1, result["version"])
    assert_equal("Test Swarm", result["swarm"]["name"])
    assert_equal("lead", result["swarm"]["main"])
    assert_equal("Lead developer", result["swarm"]["instances"]["lead"]["description"])
  end

  def test_load_config_file_with_yaml_aliases
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            prompt: &shared_prompt "You are an expert developer"
            tools: &standard_tools
              - Read
              - Edit
              - Bash
          frontend:
            description: "Frontend developer"
            prompt: *shared_prompt
            tools: *standard_tools
    YAML

    config_file = File.join(@temp_dir, "config.yml")
    File.write(config_file, yaml_content)

    result = ClaudeSwarm::YamlLoader.load_config_file(config_file)

    # Verify aliases were resolved correctly
    assert_equal(
      result["swarm"]["instances"]["lead"]["prompt"],
      result["swarm"]["instances"]["frontend"]["prompt"],
    )
    assert_equal(
      result["swarm"]["instances"]["lead"]["tools"],
      result["swarm"]["instances"]["frontend"]["tools"],
    )
    assert_equal(
      "You are an expert developer",
      result["swarm"]["instances"]["frontend"]["prompt"],
    )
    assert_equal(
      ["Read", "Edit", "Bash"],
      result["swarm"]["instances"]["frontend"]["tools"],
    )
  end

  def test_load_config_file_with_missing_file
    non_existent_file = File.join(@temp_dir, "non_existent.yml")

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::YamlLoader.load_config_file(non_existent_file)
    end

    assert_match(/Configuration file not found:/, error.message)
    assert_match(/non_existent\.yml/, error.message)
  end

  def test_load_config_file_with_invalid_yaml_syntax
    yaml_content = <<~YAML
      invalid: yaml: syntax
      missing quotes: and stuff
    YAML

    config_file = File.join(@temp_dir, "invalid.yml")
    File.write(config_file, yaml_content)

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::YamlLoader.load_config_file(config_file)
    end

    assert_match(/Invalid YAML syntax in/, error.message)
    assert_match(/invalid\.yml/, error.message)
  end

  def test_load_config_file_with_bad_alias
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        instances:
          lead:
            description: "Lead developer"
            # Reference to undefined anchor
            prompt: *undefined_anchor
    YAML

    config_file = File.join(@temp_dir, "bad_alias.yml")
    File.write(config_file, yaml_content)

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::YamlLoader.load_config_file(config_file)
    end

    assert_match(/Invalid YAML alias in/, error.message)
    assert_match(/bad_alias\.yml/, error.message)
  end

  def test_load_config_file_with_empty_yaml
    config_file = File.join(@temp_dir, "empty.yml")
    File.write(config_file, "")

    result = ClaudeSwarm::YamlLoader.load_config_file(config_file)

    # Empty YAML files return nil or false
    assert_nil(result)
  end

  def test_load_config_file_with_only_comments
    yaml_content = <<~YAML
      # This is a comment
      # Another comment
      # Yet another comment
    YAML

    config_file = File.join(@temp_dir, "comments.yml")
    File.write(config_file, yaml_content)

    result = ClaudeSwarm::YamlLoader.load_config_file(config_file)

    # YAML files with only comments return nil
    assert_nil(result)
  end

  def test_load_config_file_preserves_file_path_in_error
    # Test that the file path is properly included in all error messages
    test_cases = [
      {
        name: "missing_file",
        setup: -> { File.join(@temp_dir, "missing.yml") },
        expected_pattern: /missing\.yml/,
      },
      {
        name: "syntax_error",
        setup: -> {
          file = File.join(@temp_dir, "syntax_error.yml")
          File.write(file, "bad: yaml: content")
          file
        },
        expected_pattern: /syntax_error\.yml/,
      },
      {
        name: "bad_alias",
        setup: -> {
          file = File.join(@temp_dir, "alias_error.yml")
          File.write(file, "test: *missing")
          file
        },
        expected_pattern: /alias_error\.yml/,
      },
    ]

    test_cases.each do |test_case|
      file_path = test_case[:setup].call

      error = assert_raises(ClaudeSwarm::Error) do
        ClaudeSwarm::YamlLoader.load_config_file(file_path)
      end

      assert_match(
        test_case[:expected_pattern],
        error.message,
        "Error message should contain file path for #{test_case[:name]}",
      )
    end
  end

  def test_load_config_file_with_complex_nested_structure
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Complex Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            directory: ["/path1", "/path2", "/path3"]
            mcp_servers:
              - type: stdio
                command: ["node", "server.js"]
                args: ["--verbose"]
              - type: sse
                url: "http://localhost:3000"
            hooks:
              PreToolUse:
                - matcher: "Write|Edit"
                  hooks:
                    - type: "command"
                      command: "validate.sh"
                      timeout: 10
    YAML

    config_file = File.join(@temp_dir, "complex.yml")
    File.write(config_file, yaml_content)

    result = ClaudeSwarm::YamlLoader.load_config_file(config_file)

    assert_equal("Complex Swarm", result["swarm"]["name"])
    assert_equal(
      ["/path1", "/path2", "/path3"],
      result["swarm"]["instances"]["lead"]["directory"],
    )
    assert_equal(2, result["swarm"]["instances"]["lead"]["mcp_servers"].size)
    assert_equal("stdio", result["swarm"]["instances"]["lead"]["mcp_servers"][0]["type"])
    assert(result["swarm"]["instances"]["lead"]["hooks"]["PreToolUse"])
  end
end
