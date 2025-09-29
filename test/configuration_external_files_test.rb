# frozen_string_literal: true

require "test_helper"

class ConfigurationExternalFilesTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
    @instances_dir = File.join(@tmpdir, "instances")
    FileUtils.mkdir_p(@instances_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV.keys.select { |k| k.start_with?("TEST_ENV_") }.each { |k| ENV.delete(k) }
  end

  def write_config(content)
    File.write(@config_path, content)
  end

  def write_instance_file(filename, content)
    File.write(File.join(@instances_dir, filename), content)
  end

  def test_instance_defined_via_file_path
    # Write the external instance configuration
    write_instance_file("lead_developer.md", <<~MARKDOWN)
      ---
      description: "Lead developer from external file"
      directory: .
      model: opus
      connections: [backend]
      prompt: "You are the lead developer"
      allowed_tools: [Read, Edit]
      ---

      # Lead Developer Instance
      This is the lead developer instance configuration.
    MARKDOWN

    write_instance_file("backend.md", <<~MARKDOWN)
      ---
      description: "Backend developer from external file"
      directory: ./backend
      model: sonnet
      prompt: "You are the backend developer"
      ---

      # Backend Instance
      This is the backend developer instance configuration.
    MARKDOWN

    # Create backend directory for validation
    FileUtils.mkdir_p(File.join(@tmpdir, "backend"))

    # Write the main configuration that references the external files
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "External Files Test"
        main: lead_developer
        instances:
          lead_developer: instances/lead_developer.md
          backend: instances/backend.md
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    # Test that the configuration was loaded correctly
    assert_equal("External Files Test", config.swarm_name)
    assert_equal("lead_developer", config.main_instance)
    assert_includes(config.instance_names, "lead_developer")
    assert_includes(config.instance_names, "backend")
    assert_equal(2, config.instance_names.size)

    # Test lead_developer instance
    lead_config = config.instances["lead_developer"]

    assert_equal("Lead developer from external file", lead_config[:description])
    assert_equal("opus", lead_config[:model])
    assert_equal(["backend"], lead_config[:connections])
    assert_equal("You are the lead developer", lead_config[:prompt])
    assert_equal(["Read", "Edit"], lead_config[:allowed_tools])

    # Test backend instance
    backend_config = config.instances["backend"]

    assert_equal("Backend developer from external file", backend_config[:description])
    assert_equal("sonnet", backend_config[:model])
    assert_equal("You are the backend developer", backend_config[:prompt])
    assert_equal(File.expand_path("backend", @tmpdir), backend_config[:directory])
  end

  def test_mixed_inline_and_external_instances
    write_instance_file("frontend.md", <<~MARKDOWN)
      ---
      description: "Frontend developer from file"
      model: haiku
      prompt: "You are the frontend expert"
      ---

      # Frontend Instance
      Frontend developer configuration.
    MARKDOWN

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Mixed Config Test"
        main: lead
        instances:
          lead:
            description: "Lead developer inline"
            model: opus
            connections: [frontend, backend]
          frontend: instances/frontend.md
          backend:
            description: "Backend developer inline"
            model: sonnet
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_includes(config.instance_names, "lead")
    assert_includes(config.instance_names, "frontend")
    assert_includes(config.instance_names, "backend")
    assert_equal(3, config.instance_names.size)

    # Test inline lead instance
    assert_equal("Lead developer inline", config.instances["lead"][:description])
    assert_equal("opus", config.instances["lead"][:model])

    # Test external frontend instance
    assert_equal("Frontend developer from file", config.instances["frontend"][:description])
    assert_equal("haiku", config.instances["frontend"][:model])

    # Test inline backend instance
    assert_equal("Backend developer inline", config.instances["backend"][:description])
    assert_equal("sonnet", config.instances["backend"][:model])
  end

  def test_absolute_path_for_instance_file
    external_dir = Dir.mktmpdir
    external_file = File.join(external_dir, "external_instance.md")

    File.write(external_file, <<~MARKDOWN)
      ---
      description: "External instance with absolute path"
      model: opus
      ---

      # External Instance
      External instance with absolute path.
    MARKDOWN

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Absolute Path Test"
        main: external
        instances:
          external: #{external_file}
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("External instance with absolute path", config.instances["external"][:description])
    assert_equal("opus", config.instances["external"][:model])

    FileUtils.rm_rf(external_dir)
  end

  def test_environment_variable_interpolation_in_external_file
    ENV["TEST_ENV_MODEL"] = "claude-3-opus"
    ENV["TEST_ENV_PROMPT"] = "Custom prompt from env"

    write_instance_file("env_test.md", <<~MARKDOWN)
      ---
      description: "Instance with env vars"
      model: ${TEST_ENV_MODEL}
      prompt: ${TEST_ENV_PROMPT}
      ---

      # Env Test Instance
      Instance with environment variables.
    MARKDOWN

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Env Var Test"
        main: test
        instances:
          test: instances/env_test.md
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("claude-3-opus", config.instances["test"][:model])
    assert_equal("Custom prompt from env", config.instances["test"][:prompt])
  end

  def test_error_when_instance_file_not_found
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Missing File Test"
        main: missing
        instances:
          missing: instances/nonexistent.md
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end

    assert_match(/Instance configuration file not found for 'missing'/, error.message)
  end

  def test_error_when_external_file_has_invalid_yaml
    write_instance_file("invalid.md", <<~MARKDOWN)
      ---
      This is not: valid: YAML: content:
      ---

      # Invalid Instance
      Invalid YAML frontmatter.
    MARKDOWN

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Invalid YAML Test"
        main: invalid
        instances:
          invalid: instances/invalid.md
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end

    assert_match(/Invalid YAML syntax in frontmatter for 'invalid'/, error.message)
  end

  def test_error_when_external_file_not_a_hash
    write_instance_file("not_hash.md", <<~MARKDOWN)
      ---
      - this
      - is
      - an
      - array
      ---

      # Not Hash Instance
      Frontmatter is an array instead of a hash.
    MARKDOWN

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Not Hash Test"
        main: test
        instances:
          test: instances/not_hash.md
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end

    assert_match(/Instance configuration file for 'test' must contain valid YAML frontmatter/, error.message)
  end

  def test_error_with_invalid_instance_config_type
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Invalid Type Test"
        main: test
        instances:
          test: 123
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end

    assert_match(/Instance 'test' configuration must be either a hash or a markdown file path string/, error.message)
  end

  def test_nested_connections_with_external_files
    write_instance_file("service_a.md", <<~MARKDOWN)
      ---
      description: "Service A"
      connections: [service_b]
      ---

      # Service A
      Service A instance.
    MARKDOWN

    write_instance_file("service_b.md", <<~MARKDOWN)
      ---
      description: "Service B"
      connections: [service_c]
      ---

      # Service B
      Service B instance.
    MARKDOWN

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Nested Connections Test"
        main: service_a
        instances:
          service_a: instances/service_a.md
          service_b: instances/service_b.md
          service_c:
            description: "Service C"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal(["service_b"], config.connections_for("service_a"))
    assert_equal(["service_c"], config.connections_for("service_b"))
    assert_empty(config.connections_for("service_c"))
  end

  def test_complex_instance_with_mcps_and_hooks_from_file
    write_instance_file("complex.md", <<~MARKDOWN)
      ---
      description: "Complex instance with all features"
      model: opus
      directory: .
      vibe: true
      worktree: feature-branch
      allowed_tools: [Read, Edit, Write]
      disallowed_tools: [Bash]
      mcps:
        - name: test-mcp
          type: stdio
          command: test-server
          args: [--verbose]
      hooks:
        PreToolUse:
          - matcher: "Write|Edit"
            hooks:
              - type: command
                command: echo "Pre-tool hook"
      prompt: |
        You are a complex instance with many features.
        This is a multi-line prompt.
      ---

      # Complex Instance
      This is a complex instance with all features.
    MARKDOWN

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Complex Test"
        main: complex
        instances:
          complex: instances/complex.md
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    complex = config.instances["complex"]

    assert_equal("Complex instance with all features", complex[:description])
    assert_equal("opus", complex[:model])
    assert_nil(complex[:provider])
    assert(complex[:vibe])
    assert_equal("feature-branch", complex[:worktree])
    assert_equal(["Read", "Edit", "Write"], complex[:allowed_tools])
    assert_equal(["Bash"], complex[:disallowed_tools])
    assert_equal(1, complex[:mcps].size)
    assert_equal("test-mcp", complex[:mcps].first["name"])
    assert_equal("stdio", complex[:mcps].first["type"])
    assert(complex[:hooks])
    assert(complex[:hooks]["PreToolUse"])
    assert_match(/You are a complex instance/, complex[:prompt])
  end
end
