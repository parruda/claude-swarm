# frozen_string_literal: true

require "test_helper"
require "claude_swarm/configuration"
require "tmpdir"
require "fileutils"

class ConfigurationTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
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
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal "Test Swarm", config.swarm_name
    assert_equal "lead", config.main_instance
    assert_equal ["lead"], config.instance_names
    assert_equal File.expand_path(".", @tmpdir), config.main_instance_config[:directory]
    assert_equal "sonnet", config.main_instance_config[:model]
    assert_empty config.main_instance_config[:connections]
    assert_empty config.main_instance_config[:allowed_tools]
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
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "src"))
    Dir.mkdir(File.join(@tmpdir, "backend"))
    Dir.mkdir(File.join(@tmpdir, "frontend"))

    config = ClaudeSwarm::Configuration.new(@config_path)

    # Test main instance
    lead = config.main_instance_config

    assert_equal File.expand_path("src", @tmpdir), lead[:directory]
    assert_equal "opus", lead[:model]
    assert_equal %w[backend frontend], lead[:connections]
    assert_equal %w[Read Edit Bash], lead[:allowed_tools]
    assert_equal "You are the lead developer", lead[:prompt]

    # Test MCP servers
    assert_equal 2, lead[:mcps].length
    stdio_mcp = lead[:mcps][0]

    assert_equal "test_server", stdio_mcp["name"]
    assert_equal "stdio", stdio_mcp["type"]
    assert_equal "test-server", stdio_mcp["command"]
    assert_equal ["--verbose"], stdio_mcp["args"]

    sse_mcp = lead[:mcps][1]

    assert_equal "api_server", sse_mcp["name"]
    assert_equal "sse", sse_mcp["type"]
    assert_equal "http://localhost:3000", sse_mcp["url"]

    # Test backend instance
    backend = config.instances["backend"]

    assert_equal %w[Bash Grep], backend[:allowed_tools]

    # Test connections
    assert_equal %w[backend frontend], config.connections_for("lead")
    assert_empty config.connections_for("backend")
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
    assert_equal "Missing 'version' field in configuration", error.message
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
    assert_equal "Unsupported version: 2. Only version 1 is supported", error.message
  end

  def test_missing_swarm_field
    write_config(<<~YAML)
      version: 1
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal "Missing 'swarm' field in configuration", error.message
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
    assert_equal "Missing 'name' field in swarm configuration", error.message
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
    assert_equal "Missing 'instances' field in swarm configuration", error.message
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
    assert_equal "No instances defined", error.message
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
    assert_equal "Missing 'main' field in swarm configuration", error.message
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
    assert_equal "Main instance 'nonexistent' not found in instances", error.message
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
    assert_equal "Instance 'lead' has connection to unknown instance 'nonexistent'", error.message
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
    assert_equal "MCP configuration missing 'name'", error.message
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
    assert_equal "MCP 'test' missing 'command'", error.message
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
    assert_equal "MCP 'test' missing 'url'", error.message
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
    assert_equal "Unknown MCP type 'unknown' for 'test'", error.message
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

    assert_equal expected_path, config.main_instance_config[:directory]
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
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    lead = config.main_instance_config

    # Test defaults
    assert_equal File.expand_path(".", @tmpdir), lead[:directory]
    assert_equal "sonnet", lead[:model]
    assert_empty lead[:connections]
    assert_empty lead[:allowed_tools]
    assert_empty lead[:mcps]
    assert_nil lead[:prompt]
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
    assert_equal "Instance 'lead' missing required 'description' field", error.message
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
    assert_equal "Instance 'lead' field 'tools' must be an array, got String", error.message
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
    assert_equal "Instance 'lead' field 'allowed_tools' must be an array, got String", error.message
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
    assert_equal "Instance 'lead' field 'disallowed_tools' must be an array, got Integer", error.message
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
    assert_equal "Instance 'lead' field 'tools' must be an array, got Hash", error.message
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

    assert_empty lead[:allowed_tools]
    assert_empty lead[:allowed_tools]
    assert_empty lead[:disallowed_tools]
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

    assert_equal %w[Read Edit], lead[:allowed_tools]
    assert_equal ["Bash(rm:*)"], lead[:disallowed_tools]
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
    assert_equal "Circular dependency detected: lead -> lead", error.message
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
            connections: [worker]
          worker:
            description: "Worker instance"
            connections: [lead]
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal "Circular dependency detected: lead -> worker -> lead", error.message
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
            connections: [worker1]
          worker1:
            description: "Worker 1 instance"
            connections: [worker2]
          worker2:
            description: "Worker 2 instance"
            connections: [lead]
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal "Circular dependency detected: lead -> worker1 -> worker2 -> lead", error.message
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
            connections: [worker1]
          worker1:
            description: "Worker 1 instance"
            connections: [worker2]
          worker2:
            description: "Worker 2 instance"
            connections: [worker3]
          worker3:
            description: "Worker 3 instance"
            connections: [worker1]
    YAML

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(@config_path)
    end
    assert_equal "Circular dependency detected: worker1 -> worker2 -> worker3 -> worker1", error.message
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
            connections: [frontend, backend]
          frontend:
            description: "Frontend instance"
            connections: [ui_specialist]
          backend:
            description: "Backend instance"
            connections: [database]
          ui_specialist:
            description: "UI specialist instance"
          database:
            description: "Database instance"
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "frontend"))
    Dir.mkdir(File.join(@tmpdir, "backend"))

    # Should not raise any errors
    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal "Test", config.swarm_name
    assert_equal %w[frontend backend], config.connections_for("lead")
    assert_equal ["ui_specialist"], config.connections_for("frontend")
    assert_equal ["database"], config.connections_for("backend")
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
            connections: [frontend_lead, backend_lead, devops]
          frontend_lead:
            description: "Frontend team lead"
            connections: [react_dev, css_expert]
          backend_lead:
            description: "Backend team lead"
            connections: [api_dev, db_expert]
          react_dev:
            description: "React developer"
          css_expert:
            description: "CSS specialist"
          api_dev:
            description: "API developer"
          db_expert:
            description: "Database expert"
          devops:
            description: "DevOps engineer"
    YAML

    # Should not raise any errors
    config = ClaudeSwarm::Configuration.new(@config_path)

    assert_equal "Complex Hierarchy", config.swarm_name
    assert_equal 8, config.instances.size
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

    assert_equal 3, lead[:directories].size
    assert_equal dir1, lead[:directory] # First directory for backward compatibility
    assert_equal [dir1, dir2, dir3], lead[:directories]
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

    assert_equal 1, lead[:directories].size
    assert_equal @tmpdir, lead[:directory]
    assert_equal [@tmpdir], lead[:directories]
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
end
