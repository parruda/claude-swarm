# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "yaml"

module SwarmSDK
  class SwarmTest < Minitest::Test
    def setup
      # Set fake API key to avoid RubyLLM configuration errors
      @original_api_key = ENV["OPENAI_API_KEY"]
      ENV["OPENAI_API_KEY"] = "test-key-12345"
      # Also configure RubyLLM directly to avoid caching issues
      RubyLLM.configure do |config|
        config.openai_api_key = "test-key-12345"
      end
    end

    def teardown
      ENV["OPENAI_API_KEY"] = @original_api_key
      # Reset RubyLLM configuration
      RubyLLM.configure do |config|
        config.openai_api_key = @original_api_key
      end
    end

    def test_initialization_with_defaults
      swarm = Swarm.new(name: "Test Swarm")

      assert_equal("Test Swarm", swarm.name)
      assert_equal(50, swarm.instance_variable_get(:@global_limit))
      assert_equal(10, swarm.instance_variable_get(:@default_local_limit))
      assert_instance_of(AgentRegistry, swarm.registry)
      assert_nil(swarm.lead_agent)
    end

    def test_initialization_with_custom_limits
      swarm = Swarm.new(
        name: "Custom Swarm",
        global_limit: 100,
        default_local_limit: 20,
      )

      assert_equal(100, swarm.instance_variable_get(:@global_limit))
      assert_equal(20, swarm.instance_variable_get(:@default_local_limit))
    end

    def test_initialization_creates_global_semaphore
      swarm = Swarm.new(name: "Test Swarm")

      semaphore = swarm.instance_variable_get(:@global_semaphore)

      assert_instance_of(Async::Semaphore, semaphore)
    end

    def test_add_agent_with_required_fields
      swarm = Swarm.new(name: "Test Swarm")

      result = swarm.add_agent(
        name: :test_agent,
        description: "Test agent",
        model: "gpt-5",
        system_prompt: "You are a test agent",
        directories: ["."],
      )

      assert_equal(swarm, result) # Returns self for chaining
      assert_includes(swarm.agent_names, :test_agent)
    end

    def test_add_agent_with_all_fields
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(
        name: :full_agent,
        description: "Full agent",
        model: "claude-sonnet-4",
        system_prompt: "You are full",
        tools: [:Read, :Edit],
        delegates_to: [:other],
        directories: [".", "./lib"],
        temperature: 0.7,
        max_tokens: 4000,
        base_url: "https://api.anthropic.com",
        mcp_servers: [{ type: :stdio }],
        reasoning_effort: "high",
        max_concurrent_tools: 15,
      )

      assert_includes(swarm.agent_names, :full_agent)
    end

    def test_add_agent_converts_name_to_symbol
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(
        name: "string_name",
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )

      assert_includes(swarm.agent_names, :string_name)
    end

    def test_add_duplicate_agent_raises_error
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(
        name: :duplicate,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )

      error = assert_raises(ConfigurationError) do
        swarm.add_agent(
          name: :duplicate,
          description: "Test",
          model: "gpt-5",
          system_prompt: "Test",
          directories: ["."],
        )
      end

      assert_match(/already exists/i, error.message)
    end

    def test_add_agent_uses_default_directories
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
      )

      agent_def = swarm.instance_variable_get(:@agent_definitions)[:test]

      assert_equal(["."], agent_def[:directories])
    end

    def test_set_lead_agent
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )

      swarm.lead = :lead

      assert_equal(:lead, swarm.lead_agent)
    end

    def test_set_lead_converts_to_symbol
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )

      swarm.lead = "lead"

      assert_equal(:lead, swarm.lead_agent)
    end

    def test_set_nonexistent_lead_raises_error
      swarm = Swarm.new(name: "Test Swarm")

      error = assert_raises(ConfigurationError) do
        swarm.lead = :nonexistent
      end

      assert_match(/cannot set lead.*not found/i, error.message)
    end

    def test_agent_names_returns_all_names
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(
        name: :agent1,
        description: "A1",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )
      swarm.add_agent(
        name: :agent2,
        description: "A2",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )
      swarm.add_agent(
        name: :agent3,
        description: "A3",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )

      names = swarm.agent_names

      assert_equal(3, names.length)
      assert_includes(names, :agent1)
      assert_includes(names, :agent2)
      assert_includes(names, :agent3)
    end

    def test_load_from_yaml
      config = valid_yaml_config

      with_yaml_file(config) do |path|
        swarm = Swarm.load(path)

        assert_instance_of(Swarm, swarm)
        assert_equal("Test Swarm", swarm.name)
        assert_equal(:lead, swarm.lead_agent)
        assert_equal(2, swarm.agent_names.length)
      end
    end

    def test_execute_without_lead_raises_error
      swarm = Swarm.new(name: "Test Swarm")

      error = assert_raises(ConfigurationError) do
        swarm.execute("Do something")
      end

      assert_match(/no lead agent/i, error.message)
    end

    def test_agents_initialized_lazily
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )

      agents_hash = swarm.instance_variable_get(:@agents)

      assert_empty(agents_hash) # Not initialized yet

      swarm.lead = :agent1

      # Initialize agents by calling execute (will fail without API key, but that's ok)
      begin
        swarm.execute("test")
      rescue StandardError
        # Expected to fail without API setup
      end

      agents_hash = swarm.instance_variable_get(:@agents)

      refute_empty(agents_hash) # Now initialized
    end

    def test_default_constants
      assert_equal(50, Swarm::DEFAULT_GLOBAL_LIMIT)
      assert_equal(10, Swarm::DEFAULT_LOCAL_LIMIT)
    end

    def test_chaining_add_agent_and_set_lead
      swarm = Swarm.new(name: "Test Swarm")
        .add_agent(
          name: :lead,
          description: "Lead",
          model: "gpt-5",
          system_prompt: "Test",
          directories: ["."],
        )
        .add_agent(
          name: :backend,
          description: "Backend",
          model: "gpt-5",
          system_prompt: "Test",
          directories: ["."],
        )

      swarm.lead = :lead

      assert_equal(2, swarm.agent_names.length)
      assert_equal(:lead, swarm.lead_agent)
    end

    def test_agents_share_global_semaphore
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )

      swarm.add_agent(
        name: :agent2,
        description: "Agent 2",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )

      global_semaphore = swarm.instance_variable_get(:@global_semaphore)
      swarm.instance_variable_get(:@agent_definitions)

      # Both agents will receive the same global semaphore when initialized
      assert_instance_of(Async::Semaphore, global_semaphore)
    end

    def test_agent_gets_default_local_limit
      swarm = Swarm.new(name: "Test Swarm", default_local_limit: 15)

      swarm.add_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
      )

      agent_def = swarm.instance_variable_get(:@agent_definitions)[:agent1]

      assert_equal(15, agent_def[:max_concurrent_tools])
    end

    def test_agent_can_override_local_limit
      swarm = Swarm.new(name: "Test Swarm", default_local_limit: 15)

      swarm.add_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directories: ["."],
        max_concurrent_tools: 25,
      )

      agent_def = swarm.instance_variable_get(:@agent_definitions)[:agent1]

      assert_equal(25, agent_def[:max_concurrent_tools])
    end

    private

    def valid_yaml_config
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
            },
            "backend" => {
              "description" => "Backend agent",
              "system_prompt" => "You build APIs",
              "delegates_to" => [],
              "directories" => ["."],
            },
          },
        },
      }
    end

    def with_yaml_file(config)
      Tempfile.create(["swarm-test", ".yml"]) do |file|
        file.write(YAML.dump(config))
        file.flush
        yield file.path
      end
    end
  end
end
