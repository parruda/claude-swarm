# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "tmpdir"

class ConfigurationMarkdownTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @temp_files = []
  end

  def teardown
    @temp_files.each(&:close!)
    FileUtils.rm_rf(@temp_dir)
  end

  def test_loads_markdown_instance_file
    # Create markdown instance file
    create_file_in_dir("frontend.md", <<~MARKDOWN)
      ---
      description: "Frontend developer expert"
      directory: .
      model: sonnet
      allowed_tools: [Read, Edit]
      ---

      You are a frontend developer specializing in React.
    MARKDOWN

    # Create main config referencing the markdown file
    config_yml = create_file_in_dir("claude-swarm.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            directory: .
          frontend: ./frontend.md
    YAML

    config = ClaudeSwarm::Configuration.new(config_yml)

    assert_equal("Frontend developer expert", config.instances["frontend"][:description])
    assert_equal("sonnet", config.instances["frontend"][:model])
    assert_equal(["Read", "Edit"], config.instances["frontend"][:allowed_tools])
    assert_includes(config.instances["frontend"][:prompt], "frontend developer specializing in React")
  end

  def test_loads_multiple_markdown_instances
    # Create markdown instances
    create_file_in_dir("backend.md", <<~MARKDOWN)
      ---
      description: "Backend developer"
      directory: .
      model: opus
      ---

      Backend developer with API expertise.
    MARKDOWN

    create_file_in_dir("frontend.md", <<~MARKDOWN)
      ---
      description: "Frontend developer"
      directory: .
      model: sonnet
      ---

      Frontend developer with React expertise.
    MARKDOWN

    # Create main config
    config_yml = create_file_in_dir("claude-swarm.yml", <<~YAML)
      version: 1
      swarm:
        name: "Multiple Markdown Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            directory: .
          backend: ./backend.md
          frontend: ./frontend.md
    YAML

    config = ClaudeSwarm::Configuration.new(config_yml)

    # Check backend instance
    assert_equal("Backend developer", config.instances["backend"][:description])
    assert_equal("opus", config.instances["backend"][:model])
    assert_includes(config.instances["backend"][:prompt], "Backend developer with API expertise")

    # Check frontend instance
    assert_equal("Frontend developer", config.instances["frontend"][:description])
    assert_equal("sonnet", config.instances["frontend"][:model])
    assert_includes(config.instances["frontend"][:prompt], "Frontend developer with React expertise")
  end

  def test_handles_relative_paths_to_markdown_files
    # Create subdirectory with markdown file
    FileUtils.mkdir_p(File.join(@temp_dir, "instances"))
    create_file_in_dir("instances/api_dev.md", <<~MARKDOWN)
      ---
      description: "API developer"
      directory: .
      ---

      API development specialist.
    MARKDOWN

    config_yml = create_file_in_dir("claude-swarm.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            directory: .
          api: instances/api_dev.md
    YAML

    config = ClaudeSwarm::Configuration.new(config_yml)

    assert_equal("API developer", config.instances["api"][:description])
  end

  def test_handles_absolute_paths_to_markdown_files
    create_file_in_dir("absolute_instance.md", <<~MARKDOWN)
      ---
      description: "Absolute path instance"
      directory: .
      ---
    MARKDOWN

    absolute_path = File.join(@temp_dir, "absolute_instance.md")

    config_yml = create_file_in_dir("claude-swarm.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            directory: .
          absolute: #{absolute_path}
    YAML

    config = ClaudeSwarm::Configuration.new(config_yml)

    assert_equal("Absolute path instance", config.instances["absolute"][:description])
  end

  def test_raises_error_for_invalid_markdown_frontmatter
    create_file_in_dir("invalid.md", <<~MARKDOWN)
      ---
      description: "Invalid"
      directory: .
      invalid_yaml: [unclosed
      ---
    MARKDOWN

    config_yml = create_file_in_dir("claude-swarm.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            directory: .
          invalid: ./invalid.md
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(config_yml)
    end

    assert_includes(error.message, "Invalid YAML")
  end

  def test_handles_markdown_with_connections
    create_file_in_dir("connected.md", <<~MARKDOWN)
      ---
      description: "Connected instance"
      directory: .
      connections: [helper]
      ---

      Instance with connections.
    MARKDOWN

    create_file_in_dir("helper.md", <<~MARKDOWN)
      ---
      description: "Helper instance"
      directory: .
      ---
    MARKDOWN

    config_yml = create_file_in_dir("claude-swarm.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: connected
        instances:
          connected: ./connected.md
          helper: ./helper.md
    YAML

    config = ClaudeSwarm::Configuration.new(config_yml)

    assert_equal(["helper"], config.instances["connected"][:connections])
  end

  def test_raises_error_for_yaml_file_as_instance
    # Create a YAML file (not markdown)
    create_file_in_dir("not_markdown.yml", <<~YAML)
      description: "Instance in YAML file"
      directory: .
      model: sonnet
    YAML

    config_yml = create_file_in_dir("claude-swarm.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            directory: .
          invalid: ./not_markdown.yml
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(config_yml)
    end

    assert_match(/Instance configuration file for 'invalid' must be a markdown file/, error.message)
    assert_match(/\.md or \.markdown/, error.message)
  end

  private

  def create_file_in_dir(filename, content)
    path = File.join(@temp_dir, filename)
    File.write(path, content)
    path
  end
end
