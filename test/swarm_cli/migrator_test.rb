# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class MigratorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm-v1.yml")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def write_v1_config(content)
    File.write(@config_path, content)
  end

  def test_basic_migration
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Team"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            directory: .
            model: opus
            connections: [backend]
            prompt: "You are the lead"
          backend:
            description: "Backend developer"
            directory: .
            model: sonnet
            prompt: "You are a backend dev"
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    assert_equal(2, result["version"])
    assert_equal("Test Team", result["swarm"]["name"])
    assert_equal("lead", result["swarm"]["lead"])
    assert(result["swarm"]["agents"])
    refute(result["swarm"]["instances"])

    lead = result["swarm"]["agents"]["lead"]

    assert_equal("Lead developer", lead["description"])
    assert_equal("opus", lead["model"])
    assert_equal(["backend"], lead["delegates_to"])
    assert_equal("You are the lead", lead["system_prompt"])
    refute(lead["prompt"])
    refute(lead["connections"])

    backend = result["swarm"]["agents"]["backend"]

    assert_empty(backend["delegates_to"])
    assert_equal("You are a backend dev", backend["system_prompt"])
  end

  def test_version_validation
    write_v1_config(<<~YAML)
      version: 2
      swarm:
        name: "Test"
        lead: lead
        agents:
          lead:
            description: "Lead"
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    error = assert_raises(SwarmCLI::ExecutionError) do
      migrator.migrate
    end

    assert_match(/not a v1 configuration/, error.message)
  end

  def test_mcp_servers_migration
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            mcps:
              - name: "browser"
                type: "stdio"
                command: "bundle"
                args: ["exec", "hbt", "stdio"]
              - name: "api"
                type: "sse"
                url: "http://localhost:3000"
                timeout: 30
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    mcp_servers = result["swarm"]["agents"]["lead"]["mcp_servers"]

    assert_equal(2, mcp_servers.size)

    assert_equal("browser", mcp_servers[0]["name"])
    assert_equal("stdio", mcp_servers[0]["type"])
    assert_equal("bundle", mcp_servers[0]["command"])
    assert_equal(["exec", "hbt", "stdio"], mcp_servers[0]["args"])

    assert_equal("api", mcp_servers[1]["name"])
    assert_equal("sse", mcp_servers[1]["type"])
    assert_equal("http://localhost:3000", mcp_servers[1]["url"])
    assert_equal(30, mcp_servers[1]["timeout"])

    refute(result["swarm"]["agents"]["lead"]["mcps"])
  end

  def test_allowed_tools_migration
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            allowed_tools: [Read, Write, Edit, Bash]
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    tools = result["swarm"]["agents"]["lead"]["tools"]

    assert_equal(["Read", "Write", "Edit", "Bash"], tools)
    refute(result["swarm"]["agents"]["lead"]["allowed_tools"])
  end

  def test_vibe_true_migration
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            vibe: true
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    assert(result["swarm"]["agents"]["lead"]["bypass_permissions"])
    refute(result["swarm"]["agents"]["lead"]["vibe"])
  end

  def test_vibe_false_not_migrated
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            vibe: false
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    refute(result["swarm"]["agents"]["lead"]["bypass_permissions"])
    refute(result["swarm"]["agents"]["lead"]["vibe"])
  end

  def test_reasoning_effort_migration
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            reasoning_effort: "high"
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    assert_equal("high", result["swarm"]["agents"]["lead"]["parameters"]["reasoning"])
    refute(result["swarm"]["agents"]["lead"]["reasoning_effort"])
  end

  def test_reasoning_effort_merges_with_existing_parameters
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            reasoning_effort: "high"
            parameters:
              temperature: 0.7
              max_tokens: 1000
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    params = result["swarm"]["agents"]["lead"]["parameters"]

    assert_equal("high", params["reasoning"])
    assert_in_delta(0.7, params["temperature"])
    assert_equal(1000, params["max_tokens"])
    refute(result["swarm"]["agents"]["lead"]["reasoning_effort"])
  end

  def test_provider_base_url_api_version_preserved
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            provider: openai
            base_url: "http://localhost:3000/v1"
            api_version: "v1/responses"
            model: gpt-5
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    agent = result["swarm"]["agents"]["lead"]

    assert_equal("openai", agent["provider"])
    assert_equal("http://localhost:3000/v1", agent["base_url"])
    assert_equal("v1/responses", agent["api_version"])
    assert_equal("gpt-5", agent["model"])
  end

  def test_empty_connections_becomes_empty_array
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            connections: []
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    assert_empty(result["swarm"]["agents"]["lead"]["delegates_to"])
  end

  def test_no_connections_field_becomes_empty_array
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    assert_empty(result["swarm"]["agents"]["lead"]["delegates_to"])
  end

  def test_complex_full_migration_structure
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Full Team"
        main: architect
        instances:
          architect:
            description: "System architect"
          backend:
            description: "Backend dev"
          frontend:
            description: "Frontend dev"
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    # Verify top-level structure
    assert_equal(2, result["version"])
    assert_equal("Full Team", result["swarm"]["name"])
    assert_equal("architect", result["swarm"]["lead"])
    assert(result["swarm"]["agents"])
    refute(result["swarm"]["instances"])
  end

  def test_complex_architect_agent
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Full Team"
        main: architect
        instances:
          architect:
            description: "System architect"
            directory: .
            model: opus
            connections: [backend, frontend]
            prompt: "You are the architect"
            allowed_tools: [Read, Write, Edit]
            vibe: true
            reasoning_effort: "high"
            provider: openai
            base_url: "http://localhost:3000/v1"
            parameters:
              temperature: 0.9
            mcps:
              - name: "browser"
                type: "stdio"
                command: "bundle"
                args: ["exec", "hbt", "stdio"]
          backend:
            description: "Backend dev"
          frontend:
            description: "Frontend dev"
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    architect = result["swarm"]["agents"]["architect"]

    assert_equal("System architect", architect["description"])
    assert_equal("opus", architect["model"])
    assert_equal(["backend", "frontend"], architect["delegates_to"])
    assert_equal("You are the architect", architect["system_prompt"])
    assert_equal(["Read", "Write", "Edit"], architect["tools"])
    assert(architect["bypass_permissions"])
    assert_equal("openai", architect["provider"])
    assert_equal("http://localhost:3000/v1", architect["base_url"])
    assert_equal("high", architect["parameters"]["reasoning"])
    assert_in_delta(0.9, architect["parameters"]["temperature"])
    assert_equal(1, architect["mcp_servers"].size)

    # Verify old fields are removed
    refute(architect["connections"])
    refute(architect["prompt"])
    refute(architect["allowed_tools"])
    refute(architect["vibe"])
    refute(architect["reasoning_effort"])
    refute(architect["mcps"])
  end

  def test_complex_other_agents
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Full Team"
        main: architect
        instances:
          architect:
            description: "System architect"
          backend:
            description: "Backend dev"
            directory: ./backend
            model: sonnet
            prompt: "You are backend dev"
            allowed_tools: [Bash, Grep]
          frontend:
            description: "Frontend dev"
            directory: ./frontend
            model: sonnet
            connections: []
            prompt: "You are frontend dev"
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    # Verify backend
    backend = result["swarm"]["agents"]["backend"]

    assert_equal("Backend dev", backend["description"])
    assert_equal("./backend", backend["directory"])
    assert_empty(backend["delegates_to"])
    assert_equal("You are backend dev", backend["system_prompt"])
    assert_equal(["Bash", "Grep"], backend["tools"])

    # Verify frontend
    frontend = result["swarm"]["agents"]["frontend"]

    assert_empty(frontend["delegates_to"])
    assert_equal("You are frontend dev", frontend["system_prompt"])
  end

  def test_permissions_field_preserved
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            permissions:
              Bash:
                denied_commands: ["^rm.*"]
              Read:
                allowed_paths: ["src/**/*"]
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    permissions = result["swarm"]["agents"]["lead"]["permissions"]

    assert(permissions)
    assert_equal(["^rm.*"], permissions["Bash"]["denied_commands"])
    assert_equal(["src/**/*"], permissions["Read"]["allowed_paths"])
  end

  def test_tools_field_when_allowed_tools_not_present
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            tools: [Read, Write]
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    # Should preserve tools if allowed_tools not present
    assert_equal(["Read", "Write"], result["swarm"]["agents"]["lead"]["tools"])
  end

  def test_allowed_tools_takes_precedence_over_tools
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            allowed_tools: [Read, Write, Edit]
            tools: [Bash]
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    # allowed_tools should win
    assert_equal(["Read", "Write", "Edit"], result["swarm"]["agents"]["lead"]["tools"])
  end

  def test_multiple_agents_with_mixed_configs
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Mixed Team"
        main: lead
        instances:
          lead:
            description: "Lead"
            connections: [worker1, worker2]
            prompt: "Lead prompt"
            allowed_tools: [Read]
            vibe: true
          worker1:
            description: "Worker 1"
            prompt: "Worker 1 prompt"
            reasoning_effort: "medium"
          worker2:
            description: "Worker 2"
            prompt: "Worker 2 prompt"
            mcps:
              - name: "test"
                type: "stdio"
                command: "test-cmd"
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    agents = result["swarm"]["agents"]

    # Lead
    assert_equal(["worker1", "worker2"], agents["lead"]["delegates_to"])
    assert_equal("Lead prompt", agents["lead"]["system_prompt"])
    assert_equal(["Read"], agents["lead"]["tools"])
    assert(agents["lead"]["bypass_permissions"])

    # Worker1
    assert_empty(agents["worker1"]["delegates_to"])
    assert_equal("Worker 1 prompt", agents["worker1"]["system_prompt"])
    assert_equal("medium", agents["worker1"]["parameters"]["reasoning"])

    # Worker2
    assert_empty(agents["worker2"]["delegates_to"])
    assert_equal("Worker 2 prompt", agents["worker2"]["system_prompt"])
    assert_equal(1, agents["worker2"]["mcp_servers"].size)
  end

  def test_missing_version_raises_error
    write_v1_config(<<~YAML)
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    error = assert_raises(SwarmCLI::ExecutionError) do
      migrator.migrate
    end

    assert_match(/not a v1 configuration/, error.message)
  end

  def test_nil_connections_becomes_empty_array
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            connections:
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    assert_empty(result["swarm"]["agents"]["lead"]["delegates_to"])
  end

  def test_yaml_output_is_valid
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            prompt: "You are the lead"
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    yaml_output = migrator.migrate

    # Should be parseable
    result = YAML.safe_load(yaml_output)

    assert(result)
    assert_equal(2, result["version"])
  end

  def test_preserves_yaml_structure
    write_v1_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead"
            model: opus
            directory: .
    YAML

    migrator = SwarmCLI::Migrator.new(@config_path)
    result = YAML.safe_load(migrator.migrate)

    # Verify structure is preserved
    assert_equal(".", result["swarm"]["agents"]["lead"]["directory"])
    assert_equal("opus", result["swarm"]["agents"]["lead"]["model"])
  end
end
