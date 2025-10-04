# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "yaml"

module SwarmSDK
  class ConfigurationTest < Minitest::Test
    def test_load_valid_configuration
      with_config_file(valid_config) do |path|
        config = Configuration.load(path)

        assert_instance_of(Configuration, config)
        assert_equal("Test Swarm", config.swarm_name)
        assert_equal(:lead, config.lead_agent)
        assert_equal(2, config.agents.size)
      end
    end

    def test_missing_configuration_file_raises_error
      error = assert_raises(ConfigurationError) do
        Configuration.load("/nonexistent/path.yml")
      end

      assert_match(/configuration file not found/i, error.message)
    end

    def test_invalid_yaml_syntax_raises_error
      with_config_file("invalid: yaml: syntax: [") do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/invalid yaml syntax/i, error.message)
      end
    end

    def test_missing_version_field_raises_error
      config = valid_config
      config.delete("version")

      with_config_file(config) do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/missing 'version' field/i, error.message)
      end
    end

    def test_unsupported_version_raises_error
      config = valid_config
      config["version"] = 1

      with_config_file(config) do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/version: 2/i, error.message)
      end
    end

    def test_missing_swarm_field_raises_error
      config = { "version" => 2 }

      with_config_file(config) do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/missing 'swarm' field/i, error.message)
      end
    end

    def test_missing_name_in_swarm_raises_error
      config = valid_config
      config["swarm"].delete("name")

      with_config_file(config) do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/missing 'name' field/i, error.message)
      end
    end

    def test_missing_lead_in_swarm_raises_error
      config = valid_config
      config["swarm"].delete("lead")

      with_config_file(config) do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/missing 'lead' field/i, error.message)
      end
    end

    def test_missing_agents_in_swarm_raises_error
      config = valid_config
      config["swarm"].delete("agents")

      with_config_file(config) do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/missing 'agents' field/i, error.message)
      end
    end

    def test_empty_agents_raises_error
      config = valid_config
      config["swarm"]["agents"] = {}

      with_config_file(config) do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/no agents defined/i, error.message)
      end
    end

    def test_nonexistent_lead_agent_raises_error
      config = valid_config
      config["swarm"]["lead"] = "nonexistent"

      with_config_file(config) do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/lead agent.*not found/i, error.message)
      end
    end

    def test_circular_dependency_raises_error
      config = {
        "version" => 2,
        "swarm" => {
          "name" => "Circular",
          "lead" => "agent1",
          "agents" => {
            "agent1" => {
              "description" => "Agent 1",
              "system_prompt" => "Test",
              "delegates_to" => ["agent2"],
              "directories" => ["."],
            },
            "agent2" => {
              "description" => "Agent 2",
              "system_prompt" => "Test",
              "delegates_to" => ["agent3"],
              "directories" => ["."],
            },
            "agent3" => {
              "description" => "Agent 3",
              "system_prompt" => "Test",
              "delegates_to" => ["agent1"],
              "directories" => ["."],
            },
          },
        },
      }

      with_config_file(config) do |path|
        error = assert_raises(CircularDependencyError) do
          Configuration.load(path)
        end

        assert_match(/circular dependency detected/i, error.message)
      end
    end

    def test_unknown_connection_raises_error
      config = valid_config
      config["swarm"]["agents"]["lead"]["delegates_to"] = ["nonexistent"]

      with_config_file(config) do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/connection to unknown agent/i, error.message)
      end
    end

    def test_deep_symbolization_of_yaml_keys
      with_config_file(valid_config) do |path|
        configuration = Configuration.load(path)
        raw_config = configuration.instance_variable_get(:@config)

        # Top-level keys
        assert(raw_config.keys.all? { |k| k.is_a?(Symbol) })

        # Swarm keys
        assert(raw_config[:swarm].keys.all? { |k| k.is_a?(Symbol) })

        # Agent config keys
        agent_config = raw_config[:swarm][:agents][:lead]

        assert(agent_config.keys.all? { |k| k.is_a?(Symbol) })
      end
    end

    def test_nested_hash_symbolization
      config = valid_config
      config["swarm"]["agents"]["lead"]["mcp_servers"] = [
        { "type" => "stdio", "command" => "test" },
      ]

      with_config_file(config) do |path|
        configuration = Configuration.load(path)
        raw_config = configuration.instance_variable_get(:@config)

        mcp_servers = raw_config[:swarm][:agents][:lead][:mcp_servers]

        assert(mcp_servers.first.keys.all? { |k| k.is_a?(Symbol) })
      end
    end

    def test_agent_names_returns_all_agent_names
      with_config_file(valid_config) do |path|
        config = Configuration.load(path)

        names = config.agent_names

        assert_equal(2, names.length)
        assert_includes(names, :lead)
        assert_includes(names, :backend)
      end
    end

    def test_connections_for_returns_delegates_to
      with_config_file(valid_config) do |path|
        config = Configuration.load(path)

        connections = config.connections_for(:lead)

        assert_equal([:backend], connections)
      end
    end

    def test_connections_for_nonexistent_agent_returns_empty
      with_config_file(valid_config) do |path|
        config = Configuration.load(path)

        connections = config.connections_for(:nonexistent)

        assert_empty(connections)
      end
    end

    def test_to_swarm_creates_swarm_instance
      with_config_file(valid_config) do |path|
        config = Configuration.load(path)
        swarm = config.to_swarm

        assert_instance_of(Swarm, swarm)
        assert_equal("Test Swarm", swarm.name)
        assert_equal(:lead, swarm.lead_agent)
        assert_equal([:lead, :backend], swarm.agent_names)
      end
    end

    def test_env_var_interpolation
      ENV["TEST_MODEL"] = "gpt-5-turbo"

      config = valid_config
      config["swarm"]["agents"]["lead"]["model"] = "${TEST_MODEL}"

      with_config_file(config) do |path|
        configuration = Configuration.load(path)
        lead_agent = configuration.agents[:lead]

        assert_equal("gpt-5-turbo", lead_agent.model)
      end
    ensure
      ENV.delete("TEST_MODEL")
    end

    def test_env_var_with_default
      config = valid_config
      config["swarm"]["agents"]["lead"]["model"] = "${MISSING_VAR:=default-model}"

      with_config_file(config) do |path|
        configuration = Configuration.load(path)
        lead_agent = configuration.agents[:lead]

        assert_equal("default-model", lead_agent.model)
      end
    end

    def test_missing_env_var_without_default_raises_error
      config = valid_config
      config["swarm"]["agents"]["lead"]["model"] = "${MISSING_VAR_NO_DEFAULT}"

      with_config_file(config) do |path|
        error = assert_raises(ConfigurationError) do
          Configuration.load(path)
        end

        assert_match(/environment variable.*not set/i, error.message)
      end
    end

    private

    def valid_config
      {
        "version" => 2,
        "swarm" => {
          "name" => "Test Swarm",
          "lead" => "lead",
          "agents" => {
            "lead" => {
              "description" => "Lead agent",
              "system_prompt" => "You are the lead",
              "delegates_to" => ["backend"],
              "directories" => ["."],
              "tools" => ["Read", "Edit"],
            },
            "backend" => {
              "description" => "Backend agent",
              "system_prompt" => "You build APIs",
              "delegates_to" => [],
              "directories" => ["."],
              "tools" => ["Read", "Edit", "Bash"],
            },
          },
        },
      }
    end

    def with_config_file(config)
      Tempfile.create(["swarm-test", ".yml"]) do |file|
        file.write(YAML.dump(config))
        file.flush
        yield file.path
      end
    end
  end
end
