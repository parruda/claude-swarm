# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    # Clean up any test environment variables
    ENV.keys.select { |k| k.start_with?("TEST_ENV_") }.each { |k| ENV.delete(k) }
  end

  def write_config(content)
    File.write(@config_path, content)
  end

  def test_valid_minimal_configuration
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            prompt: "Basic lead prompt"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Test Swarm", config.swarm_name)
    assert_equal("lead", config.main_instance)
    assert_equal(["lead"], config.instance_names)
    assert_equal(File.expand_path(".", @tmpdir), config.main_instance_config[:directory])
    assert_equal("sonnet", config.main_instance_config[:model])
    assert_empty(config.main_instance_config[:connections])
    assert_empty(config.main_instance_config[:allowed_tools])
  end

  def test_full_configuration
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Full Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer instance"
            directory: ./src
            model: opus
            connections: [backend, frontend]
            tools: [Read, Edit, Bash]
            prompt: "You are the lead developer"
            mcps:
              - name: "test_server"
                type: "stdio"
                command: "test-server"
                args: ["--verbose"]
              - name: "api_server"
                type: "sse"
                url: "http://localhost:3000"
          backend:
            description: "Backend developer instance"
            directory: ./backend
            model: claude-3-5-haiku-20241022
            tools: [Bash, Grep]
            prompt: "You handle backend tasks"
          frontend:
            description: "Frontend developer instance"
            directory: ./frontend
            prompt: "You handle frontend tasks"
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "src"))
    Dir.mkdir(File.join(@tmpdir, "backend"))
    Dir.mkdir(File.join(@tmpdir, "frontend"))

    config = ClaudeSwarm::Configuration.new(@config_path)

    # Test main instance
    lead = config.main_instance_config

    assert_equal(File.expand_path("src", @tmpdir), lead[:directory])
    assert_equal("opus", lead[:model])
    assert_equal(["backend", "frontend"], lead[:connections])
    assert_equal(["Read", "Edit", "Bash"], lead[:allowed_tools])
    assert_equal("You are the lead developer", lead[:prompt])

    # Test MCP servers
    assert_equal(2, lead[:mcps].length)
    stdio_mcp = lead[:mcps][0]

    assert_equal("test_server", stdio_mcp["name"])
    assert_equal("stdio", stdio_mcp["type"])
    assert_equal("test-server", stdio_mcp["command"])
    assert_equal(["--verbose"], stdio_mcp["args"])

    sse_mcp = lead[:mcps][1]

    assert_equal("api_server", sse_mcp["name"])
    assert_equal("sse", sse_mcp["type"])
    assert_equal("http://localhost:3000", sse_mcp["url"])

    # Test backend instance
    backend = config.instances["backend"]

    assert_equal(["Bash", "Grep"], backend[:allowed_tools])

    # Test connections
    assert_equal(["backend", "frontend"], config.connections_for("lead"))
    assert_empty(config.connections_for("backend"))
  end

  def test_missing_config_file
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new("/nonexistent/config.yml")
    end
    assert_match(/Configuration file not found/, error.message)
  end

  def test_invalid_yaml_syntax
    write_config("invalid: yaml: syntax:")

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_match(/Invalid YAML syntax/, error.message)
  end

  def test_missing_version
    write_config(<<~YAML)
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Missing 'version' field in configuration", error.message)
  end

  def test_unsupported_version
    write_config(<<~YAML)
      version: 2
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Unsupported version: 2. Only version 1 is supported", error.message)
  end

  def test_missing_swarm_field
    write_config(<<~YAML)
      version: 1
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Missing 'swarm' field in configuration", error.message)
  end

  def test_missing_swarm_name
    write_config(<<~YAML)
      version: 1
      swarm:
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Missing 'name' field in swarm configuration", error.message)
  end

  def test_missing_instances
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Missing 'instances' field in swarm configuration", error.message)
  end

  def test_empty_instances
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances: {}
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("No instances defined", error.message)
  end

  def test_missing_main_field
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Missing 'main' field in swarm configuration", error.message)
  end

  def test_main_instance_not_found
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: nonexistent
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Main instance 'nonexistent' not found in instances", error.message)
  end

  def test_invalid_connection
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
            connections: [nonexistent]
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Instance 'lead' has connection to unknown instance 'nonexistent'", error.message)
  end

  def test_directory_does_not_exist
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
            directory: ./nonexistent
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_match(/Directory.*nonexistent.*for instance 'lead' does not exist/, error.message)
  end

  def test_mcp_missing_name
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
            mcps:
              - type: "stdio"
                command: "test"
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("MCP configuration missing 'name'", error.message)
  end

  def test_mcp_stdio_missing_command
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
            mcps:
              - name: "test"
                type: "stdio"
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("MCP 'test' missing 'command'", error.message)
  end

  def test_mcp_sse_missing_url
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
            mcps:
              - name: "test"
                type: "sse"
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("MCP 'test' missing 'url'", error.message)
  end

  def test_mcp_unknown_type
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
            mcps:
              - name: "test"
                type: "unknown"
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Unknown MCP type 'unknown' for 'test'", error.message)
  end

  def test_relative_directory_expansion
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
            directory: ./src/../lib
    YAML

    # Create the directory
    FileUtils.mkdir_p(File.join(@tmpdir, "lib"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    expected_path = File.expand_path("lib", @tmpdir)

    assert_equal(expected_path, config.main_instance_config[:directory])
  end

  def test_default_values
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            prompt: "Default test prompt"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    lead = config.main_instance_config

    # Test defaults
    assert_equal(File.expand_path(".", @tmpdir), lead[:directory])
    assert_equal("sonnet", lead[:model])
    assert_empty(lead[:connections])
    assert_empty(lead[:allowed_tools])
    assert_empty(lead[:mcps])
    assert_equal("Default test prompt", lead[:prompt])
  end

  def test_missing_description
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            directory: .
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Instance 'lead' missing required 'description' field", error.message)
  end

  def test_tools_must_be_array
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            tools: "Read"
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Instance 'lead' field 'tools' must be an array, got String", error.message)
  end

  def test_allowed_tools_must_be_array
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            allowed_tools: Edit
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Instance 'lead' field 'allowed_tools' must be an array, got String", error.message)
  end

  def test_disallowed_tools_must_be_array
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            disallowed_tools: 123
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Instance 'lead' field 'disallowed_tools' must be an array, got Integer", error.message)
  end

  def test_tools_as_hash_raises_error
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            tools:
              read: true
              edit: false
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Instance 'lead' field 'tools' must be an array, got Hash", error.message)
  end

  def test_valid_empty_tools_array
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            tools: []
            allowed_tools: []
            disallowed_tools: []
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    lead = config.main_instance_config

    assert_empty(lead[:allowed_tools])
    assert_empty(lead[:allowed_tools])
    assert_empty(lead[:disallowed_tools])
  end

  def test_valid_tools_arrays
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            allowed_tools: [Read, Edit]
            disallowed_tools: ["Bash(rm:*)"]
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    lead = config.main_instance_config

    assert_equal(["Read", "Edit"], lead[:allowed_tools])
    assert_equal(["Bash(rm:*)"], lead[:disallowed_tools])
  end

  def test_circular_dependency_self_reference
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            connections: [lead]
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Circular dependency detected: lead -> lead", error.message)
  end

  def test_circular_dependency_two_instances
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            prompt: "Test prompt for lead"
            connections: [worker]
          worker:
            description: "Worker instance"
            prompt: "Test prompt for worker"
            connections: [lead]
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Circular dependency detected: lead -> worker -> lead", error.message)
  end

  def test_circular_dependency_three_instances
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            prompt: "Test prompt for lead"
            connections: [worker1]
          worker1:
            description: "Worker 1 instance"
            prompt: "Test prompt for worker1"
            connections: [worker2]
          worker2:
            description: "Worker 2 instance"
            prompt: "Test prompt for worker2"
            connections: [lead]
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Circular dependency detected: lead -> worker1 -> worker2 -> lead", error.message)
  end

  def test_circular_dependency_in_subtree
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            prompt: "Test prompt for lead"
            connections: [worker1]
          worker1:
            description: "Worker 1 instance"
            prompt: "Test prompt for worker1"
            connections: [worker2]
          worker2:
            description: "Worker 2 instance"
            prompt: "Test prompt for worker2"
            connections: [worker3]
          worker3:
            description: "Worker 3 instance"
            prompt: "Test prompt for worker3"
            connections: [worker1]
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Circular dependency detected: worker1 -> worker2 -> worker3 -> worker1", error.message)
  end

  def test_valid_tree_no_circular_dependency
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            prompt: "Test prompt for lead"
            connections: [frontend, backend]
          frontend:
            description: "Frontend instance"
            prompt: "Test prompt for frontend"
            connections: [ui_specialist]
          backend:
            description: "Backend instance"
            prompt: "Test prompt for backend"
            connections: [database]
          ui_specialist:
            description: "UI specialist instance"
            prompt: "Test prompt for ui_specialist"
          database:
            description: "Database instance"
            prompt: "Test prompt for database"
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "frontend"))
    Dir.mkdir(File.join(@tmpdir, "backend"))

    # Should not raise any errors
    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Test", config.swarm_name)
    assert_equal(["frontend", "backend"], config.connections_for("lead"))
    assert_equal(["ui_specialist"], config.connections_for("frontend"))
    assert_equal(["database"], config.connections_for("backend"))
  end

  def test_complex_valid_hierarchy
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Complex Hierarchy"
        main: architect
        instances:
          architect:
            description: "System architect"
            prompt: "Test prompt for architect"
            connections: [frontend_lead, backend_lead, devops]
          frontend_lead:
            description: "Frontend team lead"
            prompt: "Test prompt for frontend_lead"
            connections: [react_dev, css_expert]
          backend_lead:
            description: "Backend team lead"
            prompt: "Test prompt for backend_lead"
            connections: [api_dev, db_expert]
          react_dev:
            description: "React developer"
            prompt: "Test prompt for react_dev"
          css_expert:
            description: "CSS specialist"
            prompt: "Test prompt for css_expert"
          api_dev:
            description: "API developer"
            prompt: "Test prompt for api_dev"
          db_expert:
            description: "Database expert"
            prompt: "Test prompt for db_expert"
          devops:
            description: "DevOps engineer"
            prompt: "Test prompt for devops"
    YAML

    # Should not raise any errors
    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Complex Hierarchy", config.swarm_name)
    assert_equal(8, config.instances.size)
  end

  def test_multi_directory_support
    # Create test directories
    dir1 = File.join(@tmpdir, "dir1")
    dir2 = File.join(@tmpdir, "dir2")
    dir3 = File.join(@tmpdir, "dir3")
    FileUtils.mkdir_p([dir1, dir2, dir3])

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            directory: ["#{dir1}", "#{dir2}", "#{dir3}"]
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    lead = config.main_instance_config

    assert_equal(3, lead[:directories].size)
    assert_equal(dir1, lead[:directory]) # First directory for backward compatibility
    assert_equal([dir1, dir2, dir3], lead[:directories])
  end

  def test_single_directory_as_string
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            directory: "#{@tmpdir}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    lead = config.main_instance_config

    assert_equal(1, lead[:directories].size)
    assert_equal(@tmpdir, lead[:directory])
    assert_equal([@tmpdir], lead[:directories])
  end

  def test_multi_directory_validation_error
    # Create only one test directory
    dir1 = File.join(@tmpdir, "dir1")
    FileUtils.mkdir_p(dir1)

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            directory: ["#{dir1}", "/nonexistent/path"]
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_match(%r{Directory '/nonexistent/path' for instance 'lead' does not exist}, error.message)
  end

  def test_configuration_with_before_commands
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before:
          - "echo 'First command'"
          - "npm install"
          - "docker-compose up -d"
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal(["echo 'First command'", "npm install", "docker-compose up -d"], config.before_commands)
  end

  def test_configuration_without_before_commands
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_empty(config.before_commands)
  end

  def test_configuration_with_empty_before_commands
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before: []
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_empty(config.before_commands)
  end

  def test_instance_worktree_configuration_true
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            worktree: true
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert(config.main_instance_config[:worktree])
  end

  def test_instance_worktree_configuration_false
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            worktree: false
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    refute(config.main_instance_config[:worktree])
  end

  def test_instance_worktree_configuration_string
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            worktree: "feature-branch"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("feature-branch", config.main_instance_config[:worktree])
  end

  def test_instance_worktree_configuration_nil
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_nil(config.main_instance_config[:worktree])
  end

  def test_instance_worktree_configuration_invalid
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            worktree: 123
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_match(/Invalid worktree value/, error.message)
  end

  def test_instance_worktree_configuration_empty_string
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            worktree: ""
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_match(/Invalid worktree value/, error.message)
  end

  # OpenAI provider tests

  def test_openai_provider_with_defaults
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Claude lead"
            connections: [ai_assistant]
          ai_assistant:
            description: "OpenAI-powered assistant"
            provider: openai
            model: gpt-4o
            prompt: "You are an AI assistant"
    YAML

    # Set environment variable for test
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    config = ClaudeSwarm::Configuration.new(@config_path)
    assistant = config.instances["ai_assistant"]

    assert_equal("openai", assistant[:provider])
    assert_equal("chat_completion", assistant[:api_version])
    assert_equal("OPENAI_API_KEY", assistant[:openai_token_env])
    assert_nil(assistant[:base_url])
    assert(assistant[:vibe], "OpenAI instances should default to vibe: true")
  ensure
    ENV.delete("OPENAI_API_KEY")
  end

  def test_openai_provider_with_custom_values
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Claude lead"
            connections: [ai_assistant]
          ai_assistant:
            description: "OpenAI-powered assistant"
            provider: openai
            model: gpt-4
            temperature: 0.7
            api_version: responses
            openai_token_env: CUSTOM_OPENAI_KEY
            base_url: https://custom.openai.com/v1
            vibe: false
            prompt: "You are an AI assistant"
    YAML

    # Set custom environment variable for test
    ENV["CUSTOM_OPENAI_KEY"] = "sk-custom-test-key"

    config = ClaudeSwarm::Configuration.new(@config_path)
    assistant = config.instances["ai_assistant"]

    assert_equal("openai", assistant[:provider])
    assert_in_delta(0.7, assistant[:temperature])
    assert_equal("responses", assistant[:api_version])
    assert_equal("CUSTOM_OPENAI_KEY", assistant[:openai_token_env])
    assert_equal("https://custom.openai.com/v1", assistant[:base_url])
    refute(assistant[:vibe], "Should respect explicit vibe: false")
  ensure
    ENV.delete("CUSTOM_OPENAI_KEY")
  end

  def test_claude_provider_default
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: claude_assistant
        instances:
          claude_assistant:
            description: "Claude-powered assistant"
            model: opus
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    assistant = config.main_instance_config

    assert_nil(assistant[:provider], "Provider should be nil for Claude (default)")
    assert_nil(assistant[:temperature])
    assert_nil(assistant[:api_version])
    assert_nil(assistant[:openai_token_env])
    assert_nil(assistant[:base_url])
    refute(assistant[:vibe], "Claude instances should default to vibe: false")
  end

  def test_invalid_provider
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: assistant
        instances:
          assistant:
            description: "Assistant"
            provider: anthropic
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Instance 'assistant' has invalid provider 'anthropic'. Must be 'claude' or 'openai'", error.message)
  end

  def test_openai_fields_without_openai_provider
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: assistant
        instances:
          assistant:
            description: "Claude assistant"
            temperature: 0.5
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Instance 'assistant' has OpenAI-specific fields temperature but provider is not 'openai'", error.message)
  end

  def test_multiple_openai_fields_without_provider
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: assistant
        instances:
          assistant:
            description: "Claude assistant"
            temperature: 0.5
            api_version: chat_completion
            base_url: https://api.openai.com/v1
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_match(/Instance 'assistant' has OpenAI-specific fields/, error.message)
    assert_match(/temperature/, error.message)
    assert_match(/api_version/, error.message)
    assert_match(/base_url/, error.message)
  end

  def test_invalid_api_version
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: assistant
        instances:
          assistant:
            description: "OpenAI assistant"
            provider: openai
            api_version: completions
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Instance 'assistant' has invalid api_version 'completions'. Must be 'chat_completion' or 'responses'", error.message)
  end

  def test_mixed_claude_and_openai_instances
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Mixed Swarm"
        main: lead
        instances:
          lead:
            description: "Claude lead"
            model: opus
            connections: [openai_helper]
          openai_helper:
            description: "OpenAI helper"
            provider: openai
            model: gpt-4o
            temperature: 0.5
            prompt: "You are an OpenAI helper"
    YAML

    # Set environment variable for test
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    config = ClaudeSwarm::Configuration.new(@config_path)

    lead = config.instances["lead"]
    helper = config.instances["openai_helper"]

    assert_nil(lead[:provider])
    assert_nil(lead[:temperature])
    refute(lead[:vibe])

    assert_equal("openai", helper[:provider])
    assert_in_delta(0.5, helper[:temperature])
    assert(helper[:vibe])
  ensure
    ENV.delete("OPENAI_API_KEY")
  end

  def test_openai_instance_without_api_key_env_var
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Claude lead"
            connections: [ai_assistant]
          ai_assistant:
            description: "OpenAI-powered assistant"
            provider: openai
            model: gpt-4o
            prompt: "You are an AI assistant"
    YAML

    # Ensure the environment variable is not set
    ENV.delete("OPENAI_API_KEY")

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Environment variable 'OPENAI_API_KEY' is not set. OpenAI provider instances require an API key.", error.message)
  end

  def test_openai_instance_with_empty_api_key_env_var
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Claude lead"
            prompt: "Test prompt for lead"
            connections: [ai_assistant]
          ai_assistant:
            description: "OpenAI-powered assistant"
            prompt: "Test prompt for ai_assistant"
            provider: openai
            model: gpt-4o
    YAML

    # Set the environment variable to an empty string
    ENV["OPENAI_API_KEY"] = ""

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Environment variable 'OPENAI_API_KEY' is not set. OpenAI provider instances require an API key.", error.message)
  ensure
    ENV.delete("OPENAI_API_KEY")
  end

  def test_main_instance_cannot_have_provider_in_interactive_mode
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Main instance with OpenAI provider"
            provider: openai
            model: gpt-4o
    YAML

    # Set the required environment variable
    ENV["OPENAI_API_KEY"] = "test-key"

    # Test in interactive mode (no prompt)
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path, options: {})
    end
    assert_equal("Main instance 'lead' cannot have a provider setting in interactive mode", error.message)
  ensure
    ENV.delete("OPENAI_API_KEY")
  end

  def test_main_instance_can_have_provider_in_non_interactive_mode
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Main instance with OpenAI provider"
            provider: openai
            model: gpt-4o
    YAML

    # Set the required environment variable
    ENV["OPENAI_API_KEY"] = "test-key"

    # Test in non-interactive mode (with prompt)
    config = ClaudeSwarm::Configuration.new(@config_path, options: { prompt: "Do something" })

    assert_equal("openai", config.main_instance_config[:provider])
  ensure
    ENV.delete("OPENAI_API_KEY")
  end

  def test_main_instance_with_explicit_claude_provider
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Main instance with explicit Claude provider"
            provider: claude
    YAML

    # Should raise an error in interactive mode because main instance can't have provider
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path, options: {})
    end
    assert_equal("Main instance 'lead' cannot have a provider setting in interactive mode", error.message)
  end

  def test_main_instance_without_provider_defaults_to_claude
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Main instance without provider"
    YAML

    # Should not raise an error
    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_nil(config.main_instance_config[:provider])
  end

  def test_non_main_instance_can_use_openai_provider
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Main instance with Claude"
            connections: [assistant]
          assistant:
            description: "Assistant with OpenAI provider"
            provider: openai
            model: gpt-4o
            prompt: "You are an assistant"
    YAML

    # Set the required environment variable
    ENV["OPENAI_API_KEY"] = "test-key"

    # Should not raise an error
    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_nil(config.main_instance_config[:provider])
    assert_equal("openai", config.instances["assistant"][:provider])
  ensure
    ENV.delete("OPENAI_API_KEY")
  end

  def test_openai_instance_with_whitespace_api_key_env_var
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Claude lead"
            prompt: "Test prompt for lead"
            connections: [ai_assistant]
          ai_assistant:
            description: "OpenAI-powered assistant"
            prompt: "Test prompt for ai_assistant"
            provider: openai
            model: gpt-4o
    YAML

    # Set the environment variable to whitespace only
    ENV["OPENAI_API_KEY"] = "   "

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Environment variable 'OPENAI_API_KEY' is not set. OpenAI provider instances require an API key.", error.message)
  ensure
    ENV.delete("OPENAI_API_KEY")
  end

  def test_openai_instance_with_custom_env_var_not_set
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Claude lead"
          ai_assistant:
            description: "OpenAI-powered assistant"
            provider: openai
            model: gpt-4o
            openai_token_env: CUSTOM_OPENAI_KEY
            prompt: "You are an AI assistant"
    YAML

    # Ensure the custom environment variable is not set
    ENV.delete("CUSTOM_OPENAI_KEY")

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Environment variable 'CUSTOM_OPENAI_KEY' is not set. OpenAI provider instances require an API key.", error.message)
  end

  def test_openai_instance_with_valid_api_key_env_var
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Claude lead"
            connections: [ai_assistant]
          ai_assistant:
            description: "OpenAI-powered assistant"
            provider: openai
            model: gpt-4o
            prompt: "You are an AI assistant"
    YAML

    # Set a valid environment variable
    ENV["OPENAI_API_KEY"] = "sk-test-key-123"

    # Should not raise any errors
    config = ClaudeSwarm::Configuration.new(@config_path)
    assistant = config.instances["ai_assistant"]

    assert_equal("openai", assistant[:provider])
  ensure
    ENV.delete("OPENAI_API_KEY")
  end

  def test_mixed_providers_only_checks_openai_env_vars
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Mixed Swarm"
        main: claude_lead
        instances:
          claude_lead:
            description: "Claude lead"
            model: opus
          openai_helper:
            description: "OpenAI helper"
            provider: openai
            model: gpt-4o
            prompt: "You are an OpenAI helper"
    YAML

    # Ensure OpenAI key is not set
    ENV.delete("OPENAI_API_KEY")

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Environment variable 'OPENAI_API_KEY' is not set. OpenAI provider instances require an API key.", error.message)
  end

  def test_claude_instance_without_openai_key_works
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: claude_assistant
        instances:
          claude_assistant:
            description: "Claude assistant"
            model: opus
    YAML

    # Ensure OpenAI key is not set
    ENV.delete("OPENAI_API_KEY")

    # Should not raise any errors for Claude instances
    config = ClaudeSwarm::Configuration.new(@config_path)
    assistant = config.main_instance_config

    assert_nil(assistant[:provider])
  end

  # Environment variable interpolation tests

  def test_env_var_interpolation_in_swarm_name
    ENV["TEST_ENV_SWARM_NAME"] = "Production Swarm"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "${TEST_ENV_SWARM_NAME}"
        main: lead
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Production Swarm", config.swarm_name)
  end

  def test_env_var_interpolation_in_instance_description
    ENV["TEST_ENV_DESCRIPTION"] = "Senior developer with expertise"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "${TEST_ENV_DESCRIPTION}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Senior developer with expertise", config.main_instance_config[:description])
  end

  def test_env_var_interpolation_in_model
    ENV["TEST_ENV_MODEL"] = "opus"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            model: "${TEST_ENV_MODEL}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("opus", config.main_instance_config[:model])
  end

  def test_env_var_interpolation_in_prompt
    ENV["TEST_ENV_PROMPT"] = "You are an expert Ruby developer"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            prompt: "${TEST_ENV_PROMPT}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("You are an expert Ruby developer", config.main_instance_config[:prompt])
  end

  def test_env_var_interpolation_in_directory
    env_dir = File.join(@tmpdir, "custom_dir")
    FileUtils.mkdir_p(env_dir)
    ENV["TEST_ENV_DIRECTORY"] = env_dir

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            directory: "${TEST_ENV_DIRECTORY}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal(env_dir, config.main_instance_config[:directory])
  end

  def test_env_var_interpolation_in_arrays
    ENV["TEST_ENV_TOOL1"] = "Read"
    ENV["TEST_ENV_TOOL2"] = "Edit"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            allowed_tools: ["${TEST_ENV_TOOL1}", "${TEST_ENV_TOOL2}", "Bash"]
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal(["Read", "Edit", "Bash"], config.main_instance_config[:allowed_tools])
  end

  def test_env_var_interpolation_in_mcp_config
    ENV["TEST_ENV_MCP_NAME"] = "github-expert"
    ENV["TEST_ENV_MCP_COMMAND"] = "mcp-server-github"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            mcps:
              - name: "${TEST_ENV_MCP_NAME}"
                type: stdio
                command: "${TEST_ENV_MCP_COMMAND}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    mcp = config.main_instance_config[:mcps].first

    assert_equal("github-expert", mcp["name"])
    assert_equal("mcp-server-github", mcp["command"])
  end

  def test_env_var_interpolation_multiple_in_same_string
    ENV["TEST_ENV_PREFIX"] = "Senior"
    ENV["TEST_ENV_ROLE"] = "Developer"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "${TEST_ENV_PREFIX} ${TEST_ENV_ROLE} with expertise"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Senior Developer with expertise", config.main_instance_config[:description])
  end

  def test_env_var_interpolation_partial_string
    ENV["TEST_ENV_VERSION"] = "2.0"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "MyApp v${TEST_ENV_VERSION} Swarm"
        main: lead
        instances:
          lead:
            description: "Lead for version ${TEST_ENV_VERSION}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("MyApp v2.0 Swarm", config.swarm_name)
    assert_equal("Lead for version 2.0", config.main_instance_config[:description])
  end

  def test_env_var_not_set_raises_error
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "${UNDEFINED_ENV_VAR}"
        main: lead
        instances:
          lead:
            description: "Lead instance"
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal("Environment variable 'UNDEFINED_ENV_VAR' is not set", error.message)
  end

  def test_env_var_interpolation_in_nested_structure
    ENV["TEST_ENV_URL"] = "https://api.example.com"
    ENV["TEST_ENV_ARG"] = "--verbose"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            mcps:
              - name: "api-server"
                type: sse
                url: "${TEST_ENV_URL}"
                args:
                  - "${TEST_ENV_ARG}"
                  - "--port=8080"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    mcp = config.main_instance_config[:mcps].first

    assert_equal("https://api.example.com", mcp["url"])
    assert_equal(["--verbose", "--port=8080"], mcp["args"])
  end

  def test_env_var_interpolation_in_before_commands
    ENV["TEST_ENV_INSTALL_CMD"] = "npm install"
    ENV["TEST_ENV_BUILD_CMD"] = "npm run build"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before:
          - "${TEST_ENV_INSTALL_CMD}"
          - "${TEST_ENV_BUILD_CMD}"
          - "echo 'Setup complete'"
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal(["npm install", "npm run build", "echo 'Setup complete'"], config.before_commands)
  end

  def test_configuration_with_after_commands
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        after:
          - "echo 'Cleaning up'"
          - "docker-compose down"
          - "rm -rf temp/*"
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal(["echo 'Cleaning up'", "docker-compose down", "rm -rf temp/*"], config.after_commands)
  end

  def test_configuration_without_after_commands
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_empty(config.after_commands)
  end

  def test_configuration_with_empty_after_commands
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        after: []
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_empty(config.after_commands)
  end

  def test_configuration_with_both_before_and_after_commands
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        before:
          - "echo 'Starting...'"
          - "npm install"
        after:
          - "echo 'Stopping...'"
          - "npm run cleanup"
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal(["echo 'Starting...'", "npm install"], config.before_commands)
    assert_equal(["echo 'Stopping...'", "npm run cleanup"], config.after_commands)
  end

  def test_env_var_interpolation_in_after_commands
    ENV["TEST_ENV_CLEANUP_CMD"] = "docker-compose down"
    ENV["TEST_ENV_REMOVE_CMD"] = "rm -rf temp"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        after:
          - "${TEST_ENV_CLEANUP_CMD}"
          - "${TEST_ENV_REMOVE_CMD}"
          - "echo 'Cleanup complete'"
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal(["docker-compose down", "rm -rf temp", "echo 'Cleanup complete'"], config.after_commands)
  end

  def test_env_var_interpolation_with_special_characters
    ENV["TEST_ENV_SPECIAL"] = "Value with $pecial & ch@rs!"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "${TEST_ENV_SPECIAL}"
        main: lead
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Value with $pecial & ch@rs!", config.swarm_name)
  end

  def test_env_var_interpolation_preserves_non_env_syntax
    ENV["TEST_ENV_REAL"] = "interpolated"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test with ${TEST_ENV_REAL} and $NOT_ENV and {ALSO_NOT}"
        main: lead
        instances:
          lead:
            description: "Has ${TEST_ENV_REAL} value"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Test with interpolated and $NOT_ENV and {ALSO_NOT}", config.swarm_name)
    assert_equal("Has interpolated value", config.main_instance_config[:description])
  end

  def test_env_var_interpolation_empty_value
    ENV["TEST_ENV_EMPTY"] = ""
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test${TEST_ENV_EMPTY}Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("TestSwarm", config.swarm_name)
  end

  def test_env_var_interpolation_in_openai_config
    ENV["TEST_ENV_OPENAI_KEY"] = "CUSTOM_API_KEY"
    ENV["TEST_ENV_BASE_URL"] = "https://custom.openai.com/v1"
    ENV["CUSTOM_API_KEY"] = "sk-test-key"

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Claude lead"
            prompt: "Test prompt for lead"
            connections: [assistant]
          assistant:
            description: "OpenAI assistant"
            prompt: "Test prompt for assistant"
            provider: openai
            model: gpt-4o
            openai_token_env: "${TEST_ENV_OPENAI_KEY}"
            base_url: "${TEST_ENV_BASE_URL}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    assistant = config.instances["assistant"]

    assert_equal("CUSTOM_API_KEY", assistant[:openai_token_env])
    assert_equal("https://custom.openai.com/v1", assistant[:base_url])
  ensure
    ENV.delete("CUSTOM_API_KEY")
  end

  # Environment variable default value tests

  def test_env_var_with_default_value_when_not_set
    ENV.delete("TEST_ENV_DB_PORT") # Ensure it's not set
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "DB on port ${TEST_ENV_DB_PORT:=5432}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("DB on port 5432", config.main_instance_config[:description])
  end

  def test_env_var_with_default_value_when_set
    ENV["TEST_ENV_DB_HOST"] = "production.db"
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Connect to ${TEST_ENV_DB_HOST:=localhost}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Connect to production.db", config.main_instance_config[:description])
  end

  def test_env_var_with_empty_default_value
    ENV.delete("TEST_ENV_OPTIONAL")
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Optional: ${TEST_ENV_OPTIONAL:=}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Optional: ", config.main_instance_config[:description])
  end

  def test_multiple_env_vars_with_defaults
    ENV.delete("TEST_ENV_HOST")
    ENV["TEST_ENV_PORT"] = "8080"
    ENV.delete("TEST_ENV_PROTOCOL")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Server at ${TEST_ENV_PROTOCOL:=https}://${TEST_ENV_HOST:=example.com}:${TEST_ENV_PORT:=3000}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Server at https://example.com:8080", config.main_instance_config[:description])
  end

  def test_env_var_with_default_in_arrays
    ENV.delete("TEST_ENV_TOOL1")
    ENV["TEST_ENV_TOOL2"] = "CustomTool"

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead"
            tools: ["${TEST_ENV_TOOL1:=Read}", "${TEST_ENV_TOOL2:=Write}", "Bash"]
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal(["Read", "CustomTool", "Bash"], config.main_instance_config[:tools])
  end

  def test_env_var_with_default_containing_spaces
    ENV.delete("TEST_ENV_DESCRIPTION")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "${TEST_ENV_DESCRIPTION:=A default description with spaces}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("A default description with spaces", config.main_instance_config[:description])
  end

  def test_env_var_with_default_containing_special_chars
    ENV.delete("TEST_ENV_URL")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "${TEST_ENV_URL:=https://api.example.com/v1?key=123&format=json}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("https://api.example.com/v1?key=123&format=json", config.main_instance_config[:description])
  end

  def test_env_var_without_default_still_raises_error
    ENV.delete("TEST_ENV_REQUIRED")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "${TEST_ENV_REQUIRED}"
        main: lead
        instances:
          lead:
            description: "Lead"
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end

    assert_equal("Environment variable 'TEST_ENV_REQUIRED' is not set", error.message)
  end

  def test_env_var_with_nested_braces_in_default
    ENV.delete("TEST_ENV_JSON")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: '${TEST_ENV_JSON:={"key": "value"}}'
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal('{"key": "value"}', config.main_instance_config[:description])
  end

  def test_mixed_env_vars_with_and_without_defaults
    ENV["TEST_ENV_SET"] = "SetValue"
    ENV.delete("TEST_ENV_UNSET")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Mix: ${TEST_ENV_SET} and ${TEST_ENV_UNSET:=DefaultValue}"
            model: "${TEST_ENV_UNSET:=sonnet}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("Mix: SetValue and DefaultValue", config.main_instance_config[:description])
    assert_equal("sonnet", config.main_instance_config[:model])
  end

  def test_env_var_default_in_mcp_config
    ENV.delete("TEST_ENV_MCP_CMD")
    ENV.delete("TEST_ENV_MCP_URL")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead"
            mcps:
              - name: stdio-server
                type: stdio
                command: "${TEST_ENV_MCP_CMD:=default-mcp-server}"
                args: ["--port", "3000"]
              - name: sse-server
                type: sse
                url: "${TEST_ENV_MCP_URL:=http://localhost:8080}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    mcps = config.main_instance_config[:mcps]

    assert_equal("default-mcp-server", mcps[0]["command"])
    assert_equal("http://localhost:8080", mcps[1]["url"])
  end

  def test_env_var_default_in_worktree_string
    ENV.delete("TEST_ENV_WORKTREE")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead"
            worktree: "${TEST_ENV_WORKTREE:=feature-branch}"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal("feature-branch", config.main_instance_config[:worktree])
  end

  # Hooks configuration tests

  def test_instance_with_hooks_configuration
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            hooks:
              PreToolUse:
                - matcher: "Write|Edit"
                  hooks:
                    - type: "command"
                      command: "$CLAUDE_PROJECT_DIR/.claude/hooks/validate.py"
                      timeout: 10
              PostToolUse:
                - matcher: "Bash"
                  hooks:
                    - type: "command"
                      command: "echo 'Command executed' >> /tmp/commands.log"
              UserPromptSubmit:
                - hooks:
                    - type: "command"
                      command: "$CLAUDE_PROJECT_DIR/.claude/hooks/context.py"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    hooks = config.main_instance_config[:hooks]

    assert(hooks, "Hooks should be present")
    assert(hooks["PreToolUse"], "PreToolUse hooks should be present")
    assert_equal(1, hooks["PreToolUse"].size)
    assert_equal("Write|Edit", hooks["PreToolUse"][0]["matcher"])
    assert_equal(1, hooks["PreToolUse"][0]["hooks"].size)
    assert_equal("command", hooks["PreToolUse"][0]["hooks"][0]["type"])
    assert_equal("$CLAUDE_PROJECT_DIR/.claude/hooks/validate.py", hooks["PreToolUse"][0]["hooks"][0]["command"])
    assert_equal(10, hooks["PreToolUse"][0]["hooks"][0]["timeout"])

    assert(hooks["PostToolUse"], "PostToolUse hooks should be present")
    assert_equal("Bash", hooks["PostToolUse"][0]["matcher"])

    assert(hooks["UserPromptSubmit"], "UserPromptSubmit hooks should be present")
    assert_nil(hooks["UserPromptSubmit"][0]["matcher"], "UserPromptSubmit should not have matcher")
  end

  def test_instance_without_hooks
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_nil(config.main_instance_config[:hooks], "Hooks should be nil when not specified")
  end

  def test_multiple_instances_with_different_hooks
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            prompt: "Test prompt for lead"
            hooks:
              PreToolUse:
                - matcher: "*"
                  hooks:
                    - type: "command"
                      command: "echo 'Lead executing tool'"
          frontend:
            description: "Frontend developer"
            prompt: "Test prompt for frontend"
            hooks:
              PreToolUse:
                - matcher: "Write"
                  hooks:
                    - type: "command"
                      command: "npm run lint"
          backend:
            description: "Backend developer"
            prompt: "Test prompt for backend"
            # No hooks
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    # Check lead hooks
    lead_hooks = config.instances["lead"][:hooks]

    assert(lead_hooks["PreToolUse"])
    assert_equal("*", lead_hooks["PreToolUse"][0]["matcher"])

    # Check frontend hooks
    frontend_hooks = config.instances["frontend"][:hooks]

    assert(frontend_hooks["PreToolUse"])
    assert_equal("Write", frontend_hooks["PreToolUse"][0]["matcher"])
    assert_equal("npm run lint", frontend_hooks["PreToolUse"][0]["hooks"][0]["command"])

    # Check backend has no hooks
    assert_nil(config.instances["backend"][:hooks])
  end

  def test_hooks_with_env_var_interpolation
    ENV["TEST_ENV_HOOK_CMD"] = "python3 validate.py"
    ENV["TEST_ENV_TIMEOUT"] = "30"

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            hooks:
              PreToolUse:
                - matcher: "Write"
                  hooks:
                    - type: "command"
                      command: "${TEST_ENV_HOOK_CMD}"
                      timeout: ${TEST_ENV_TIMEOUT}
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    hook = config.main_instance_config[:hooks]["PreToolUse"][0]["hooks"][0]

    assert_equal("python3 validate.py", hook["command"])
    assert_equal("30", hook["timeout"]) # YAML parses numbers in strings as strings
  end

  # Prompt loading from file tests

  # Helper methods for prompt file tests
  def create_prompt_file(instance_name, content, config_name: nil)
    config_name ||= File.basename(@config_path, ".*")
    prompt_dir = File.join(@tmpdir, ".claude-swarm", config_name, instance_name)
    create_directories(prompt_dir)
    prompt_file = File.join(prompt_dir, "prompt.md")
    File.write(prompt_file, content)
    prompt_file
  end

  def assert_prompt_equals(config, instance_name, expected_content)
    actual = config.instances[instance_name][:prompt]

    assert_equal(expected_content, actual, "Prompt mismatch for instance '#{instance_name}'")
    assert_instance_of(String, actual) if actual && !actual.empty?
  end

  def test_load_prompt_returns_content_from_file_when_config_prompt_nil
    create_prompt_file("lead", "You are an expert Ruby developer with years of experience.")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            # No prompt specified in config
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)

      assert_prompt_equals(config, "lead", "You are an expert Ruby developer with years of experience.")
    end
  end

  def test_load_prompt_returns_config_value_when_both_config_and_file_exist
    create_prompt_file("lead", "This prompt should be ignored.")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            prompt: "This prompt from config takes precedence."
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)

      assert_prompt_equals(config, "lead", "This prompt from config takes precedence.")
    end
  end

  def test_main_instance_allows_missing_prompt
    # No prompt file created for main instance
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            # No prompt in config, no file either - OK for main instance
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_nil(config.main_instance_config[:prompt])
  end

  def test_non_main_instance_requires_prompt
    # No prompt file created for non-main instance
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            # Main instance can omit prompt
          helper:
            description: "Helper instance"
            # No prompt in config, no file either - ERROR for non-main instance
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_match(/Instance 'helper' requires a prompt/, error.message)
    assert_match(/Either provide it in the configuration file or create a prompt.md file/, error.message)
  end

  def test_load_prompt_strips_whitespace_from_file_content
    create_prompt_file("lead", "\n\n  You are an AI assistant.  \n\n")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)

      assert_prompt_equals(config, "lead", "You are an AI assistant.")
    end
  end

  def test_load_prompt_loads_different_files_for_different_instances
    create_prompt_file("lead", "Lead developer prompt")
    create_prompt_file("frontend", "Frontend developer prompt")
    create_prompt_file("backend", "Backend developer prompt")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
          frontend:
            description: "Frontend developer"
          backend:
            description: "Backend developer"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)

      assert_prompt_equals(config, "lead", "Lead developer prompt")
      assert_prompt_equals(config, "frontend", "Frontend developer prompt")
      assert_prompt_equals(config, "backend", "Backend developer prompt")
    end
  end

  def test_load_prompt_handles_yaml_extension_config_files
    yaml_config_path = File.join(@tmpdir, "custom-config.yaml")
    create_prompt_file("lead", "Prompt from YAML config file", config_name: "custom-config")

    File.write(yaml_config_path, <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(yaml_config_path)

      assert_prompt_equals(config, "lead", "Prompt from YAML config file")
    end
  end

  def test_load_prompt_handles_custom_config_filenames
    custom_config_path = File.join(@tmpdir, "my-swarm-config.yml")
    create_prompt_file("worker", "Worker instance prompt", config_name: "my-swarm-config")

    File.write(custom_config_path, <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: worker
        instances:
          worker:
            description: "Worker instance"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(custom_config_path)

      assert_prompt_equals(config, "worker", "Worker instance prompt")
    end
  end

  def test_load_prompt_returns_empty_string_for_empty_file
    create_prompt_file("lead", "")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)
      result = config.main_instance_config[:prompt]

      assert_equal("", result)
      assert_instance_of(String, result)
      refute_nil(result)
    end
  end

  def test_load_prompt_preserves_markdown_formatting
    markdown_content = <<~MD
      # System Prompt

      You are an expert software engineer with the following skills:
      - Ruby programming
      - Test-driven development
      - Code review

      ## Guidelines

      1. Write clean, maintainable code
      2. Follow best practices
      3. Add comprehensive tests
    MD

    create_prompt_file("lead", markdown_content)

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)

      assert_prompt_equals(config, "lead", markdown_content.strip)
    end
  end

  def test_load_prompt_interpolates_env_vars_in_config_prompt
    ENV["TEST_ENV_PROMPT"] = "Prompt from environment variable"

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            prompt: "${TEST_ENV_PROMPT}"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)

      assert_prompt_equals(config, "lead", "Prompt from environment variable")
    end
  end

  def test_load_prompt_handles_mixed_config_and_file_prompts
    create_prompt_file("frontend", "Frontend from file")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            prompt: "Lead from config"
          frontend:
            description: "Frontend developer"
            # Will use file
          backend:
            description: "Backend developer"
            prompt: "Backend from config"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)

      assert_prompt_equals(config, "lead", "Lead from config")
      assert_prompt_equals(config, "frontend", "Frontend from file")
      assert_prompt_equals(config, "backend", "Backend from config")
    end
  end

  def test_load_prompt_preserves_special_characters
    special_content = "You're an AI with $pecial ch@racters & symbols: <>"
    create_prompt_file("lead", special_content)

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)

      assert_prompt_equals(config, "lead", special_content)
    end
  end

  def test_load_prompt_handles_unicode_content
    unicode_content = "You are an AI assistant. 你好世界 🚀 ñ é ü ß"
    create_prompt_file("lead", unicode_content)

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)

      assert_prompt_equals(config, "lead", unicode_content)
    end
  end

  def test_load_prompt_uses_config_dir_for_relative_paths
    subdir = File.join(@tmpdir, "configs")
    create_directories(subdir)
    subdir_config_path = File.join(subdir, "team-config.yml")

    # Prompt file should be relative to config file location
    prompt_dir = File.join(subdir, ".claude-swarm", "team-config", "lead")
    create_directories(prompt_dir)
    prompt_file = File.join(prompt_dir, "prompt.md")
    File.write(prompt_file, "Prompt in subdirectory")

    File.write(subdir_config_path, <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(subdir_config_path)

      assert_prompt_equals(config, "lead", "Prompt in subdirectory")
    end
  end

  # Edge cases for prompt loading

  def test_load_prompt_handles_very_large_file
    # Test with a 5MB prompt file
    large_content = "Large prompt\n" * 400_000
    create_prompt_file("lead", large_content)

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)

      assert_prompt_equals(config, "lead", large_content.strip)
    end
  end

  def test_load_prompt_when_prompt_md_is_directory_not_file
    # Create prompt.md as a directory instead of file
    prompt_dir = File.join(@tmpdir, ".claude-swarm", "claude-swarm", "lead", "prompt.md")
    create_directories(prompt_dir)

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      error = assert_raises(ClaudeSwarm::Error) do
        ClaudeSwarm::Configuration.new(@config_path)
      end
      assert_match(/Error reading prompt file/, error.message)
    end
  end

  def test_load_prompt_with_nonexistent_directory_in_path
    # Test that prompt loading works even with unusual instance names
    # as long as the config is valid
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            directory: ./nonexistent
    YAML

    _, _err = capture_io do
      error = assert_raises(ClaudeSwarm::Error) do
        ClaudeSwarm::Configuration.new(@config_path)
      end
      # Should fail because directory doesn't exist
      assert_match(/Directory.*nonexistent.*does not exist/, error.message)
    end
  end

  def test_load_prompt_handles_whitespace_only_file
    create_prompt_file("lead", "   \n\t\n   ")

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      config = ClaudeSwarm::Configuration.new(@config_path)
      result = config.main_instance_config[:prompt]

      assert_equal("", result)
      assert_instance_of(String, result)
    end
  end

  def test_load_prompt_with_binary_file_raises_error
    # Create a file with binary content that will cause UTF-8 error
    binary_content = [0xFF, 0xD8, 0xFF, 0xE0].pack("C*") + "Some text"
    create_prompt_file("lead", binary_content)

    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
    YAML

    _, _err = capture_io do
      error = assert_raises(ClaudeSwarm::Error) do
        ClaudeSwarm::Configuration.new(@config_path)
      end
      assert_match(/Error reading prompt file.*invalid byte sequence/, error.message)
    end
  end
end
