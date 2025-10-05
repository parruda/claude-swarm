# frozen_string_literal: true

require "test_helper"

class McpGeneratorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
    @session_path = File.join(@tmpdir, "test_session")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def write_config(content)
    File.write(@config_path, content)
  end

  def test_generate_all_creates_directory
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
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    assert(Dir.exist?(@session_path), "Expected session directory to exist")
  end

  def test_generate_main_instance_config
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            connections: [backend, frontend]
            tools: [Read, Edit]
            mcps:
              - name: "test_server"
                type: "stdio"
                command: "test-cmd"
                args: ["--flag"]
          backend:
            description: "Backend instance"
            directory: ./backend
            model: claude-3-5-haiku-20241022
            tools: [Bash, Grep]
            prompt: "Backend developer"
          frontend:
            description: "Frontend instance"
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "backend"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Read generated config
    mcp_config = read_mcp_config("lead")

    # Check mcpServers section
    assert(mcp_config.key?("mcpServers"))
    servers = mcp_config["mcpServers"]

    # Check backend connection
    assert(servers.key?("backend"))
    backend = servers["backend"]

    assert_equal("stdio", backend["type"])
    assert_equal("claude-swarm", backend["command"])

    args = backend["args"]

    assert_equal("mcp-serve", args[0])
    assert_includes(args, "--name")
    assert_includes(args, "backend")
    assert_includes(args, "--directory")
    # Check that the directory arg is present - it may have different path formats
    dir_index = args.index("--directory")

    assert(dir_index, "Should have --directory flag")
    assert(args[dir_index + 1].end_with?("backend"), "Directory should end with 'backend'")
    assert_includes(args, "--model")
    assert_includes(args, "claude-3-5-haiku-20241022")
    assert_includes(args, "--prompt")
    assert_includes(args, "Backend developer")
    assert_includes(args, "--allowed-tools")
    assert_includes(args, "Bash,Grep")

    # Check frontend connection
    assert(servers.key?("frontend"))
    frontend = servers["frontend"]

    assert_equal("stdio", frontend["type"])
    assert_equal("claude-swarm", frontend["command"])

    # Check custom MCP server
    assert(servers.key?("test_server"))
    test_server = servers["test_server"]

    assert_equal("stdio", test_server["type"])
    assert_equal("test-cmd", test_server["command"])
    assert_equal(["--flag"], test_server["args"])
  end

  def test_sse_mcp_server
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            mcps:
              - name: "api_server"
                type: "sse"
                url: "http://localhost:3000/events"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    mcp_config = read_mcp_config("lead")

    api_server = mcp_config["mcpServers"]["api_server"]

    assert_equal("sse", api_server["type"])
    assert_equal("http://localhost:3000/events", api_server["url"])
    assert_nil(api_server["command"])
    assert_nil(api_server["args"])
  end

  def test_http_mcp_server
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            mcps:
              - name: "api_server"
                type: "http"
                url: "http://localhost:3000/mcp"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    mcp_config = read_mcp_config("lead")

    api_server = mcp_config["mcpServers"]["api_server"]

    assert_equal("http", api_server["type"])
    assert_equal("http://localhost:3000/mcp", api_server["url"])
    assert_nil(api_server["command"])
    assert_nil(api_server["args"])
  end

  def test_http_mcp_server_with_headers
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            mcps:
              - name: "api_server"
                type: "http"
                url: "http://localhost:3000/mcp"
                headers:
                  Authorization: "Bearer token123"
                  X-Custom-Header: "custom-value"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    mcp_config = read_mcp_config("lead")

    api_server = mcp_config["mcpServers"]["api_server"]

    assert_equal("http", api_server["type"])
    assert_equal("http://localhost:3000/mcp", api_server["url"])
    assert_equal("Bearer token123", api_server["headers"]["Authorization"])
    assert_equal("custom-value", api_server["headers"]["X-Custom-Header"])
    assert_nil(api_server["command"])
    assert_nil(api_server["args"])
  end

  def test_empty_tools_and_connections
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
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    mcp_config = read_mcp_config("lead")

    # Should have no MCP servers
    assert_equal(0, mcp_config["mcpServers"].size)
  end

  def test_generate_for_specific_instance
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            connections: [backend]
          backend:
            description: "Backend instance"
            connections: [database]
          database:
            description: "Database instance"
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "backend"))
    Dir.mkdir(File.join(@tmpdir, "database"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check backend config has database connection
    backend_config = read_mcp_config("backend")

    assert(backend_config["mcpServers"].key?("database"))

    # Check database config has no MCP servers
    database_config = read_mcp_config("database")

    assert_equal(0, database_config["mcpServers"].size)
  end

  def test_mcp_config_path_in_args
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
    YAML

    Dir.mkdir(File.join(@tmpdir, "worker"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    lead_config = read_mcp_config("lead")
    worker_args = lead_config["mcpServers"]["worker"]["args"]

    mcp_path_index = worker_args.index("--mcp-config-path")

    assert(mcp_path_index, "Should include --mcp-config-path flag")

    mcp_path = worker_args[mcp_path_index + 1]

    assert(mcp_path.end_with?("worker.mcp.json"))
    assert_path_exists(mcp_path)
  end

  def test_preserves_mcp_args_array
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            mcps:
              - name: "complex_server"
                type: "stdio"
                command: "complex-cmd"
                args: ["--port", "3000", "--verbose", "--config", "/path/to/config.json"]
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    mcp_config = read_mcp_config("lead")

    server = mcp_config["mcpServers"]["complex_server"]
    expected_args = ["--port", "3000", "--verbose", "--config", "/path/to/config.json"]

    assert_equal(expected_args, server["args"])
  end

  def test_vibe_mode_no_mcp_servers
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    # Test with vibe mode enabled
    generator = ClaudeSwarm::McpGenerator.new(config, vibe: true)

    generator.generate_all

    mcp_config = read_mcp_config("lead")

    # In vibe mode, should have no MCPs
    assert_empty(mcp_config["mcpServers"])
  end

  def test_instance_ids_are_generated
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            connections: [backend]
          backend:
            description: "Backend instance"
    YAML

    Dir.mkdir(File.join(@tmpdir, "backend"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check lead config has instance_id
    lead_config = read_mcp_config("lead")

    assert(lead_config.key?("instance_id"))
    assert(lead_config.key?("instance_name"))
    assert_equal("lead", lead_config["instance_name"])
    assert_match(/^lead_[a-f0-9]{8}$/, lead_config["instance_id"])

    # Check backend config has instance_id
    backend_config = read_mcp_config("backend")

    assert(backend_config.key?("instance_id"))
    assert(backend_config.key?("instance_name"))
    assert_equal("backend", backend_config["instance_name"])
    assert_match(/^backend_[a-f0-9]{8}$/, backend_config["instance_id"])

    # Check that connection includes calling_instance_id
    backend_connection = lead_config["mcpServers"]["backend"]

    assert_includes(backend_connection["args"], "--calling-instance-id")

    calling_id_index = backend_connection["args"].index("--calling-instance-id") + 1

    assert_equal(lead_config["instance_id"], backend_connection["args"][calling_id_index])

    # Check that connection includes instance_id for the target instance
    assert_includes(backend_connection["args"], "--instance-id")

    instance_id_index = backend_connection["args"].index("--instance-id") + 1

    assert_equal(backend_config["instance_id"], backend_connection["args"][instance_id_index])
  end

  def test_multiple_callers_get_different_ids
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            connections: [shared]
          frontend:
            description: "Frontend instance"
            connections: [shared]
          shared:
            description: "Shared service"
    YAML

    Dir.mkdir(File.join(@tmpdir, "frontend"))
    Dir.mkdir(File.join(@tmpdir, "shared"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    lead_config = read_mcp_config("lead")
    frontend_config = read_mcp_config("frontend")

    # Both should have unique instance IDs
    refute_equal(lead_config["instance_id"], frontend_config["instance_id"])

    # Check that shared service gets different calling_instance_ids from each caller
    lead_shared_connection = lead_config["mcpServers"]["shared"]
    frontend_shared_connection = frontend_config["mcpServers"]["shared"]

    lead_calling_id_index = lead_shared_connection["args"].index("--calling-instance-id") + 1
    frontend_calling_id_index = frontend_shared_connection["args"].index("--calling-instance-id") + 1

    assert_equal(lead_config["instance_id"], lead_shared_connection["args"][lead_calling_id_index])
    assert_equal(frontend_config["instance_id"], frontend_shared_connection["args"][frontend_calling_id_index])
  end

  def test_openai_instance_gets_claude_tools_mcp
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Claude lead"
            directory: .
            connections: [openai_assistant]
          openai_assistant:
            description: "OpenAI instance"
            directory: .
            provider: openai
            model: gpt-4o
    YAML

    # Set environment variable for test
    ENV["OPENAI_API_KEY"] = "sk-test-key"

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check that OpenAI instance has claude_tools MCP server
    config_json = read_mcp_config("openai_assistant")

    assert(config_json["mcpServers"].key?("claude_tools"), "OpenAI instance should have claude_tools MCP server")

    claude_tools_config = config_json["mcpServers"]["claude_tools"]

    assert_equal("stdio", claude_tools_config["type"])
    assert_equal("claude", claude_tools_config["command"])
    assert_equal(["mcp", "serve"], claude_tools_config["args"])
  ensure
    ENV.delete("OPENAI_API_KEY")
  end

  def test_claude_instance_no_claude_tools_mcp
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: claude_assistant
        instances:
          claude_assistant:
            description: "Claude instance"
            directory: .
            model: opus
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check that Claude instance does NOT have claude_tools MCP server
    config_json = read_mcp_config("claude_assistant")

    refute(config_json["mcpServers"].key?("claude_tools"), "Claude instance should NOT have claude_tools MCP server")
  end

  private

  def read_mcp_config(instance_name)
    JSON.parse(File.read(File.join(@session_path, "#{instance_name}.mcp.json")))
  end
end
