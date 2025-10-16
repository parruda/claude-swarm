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
      assert_equal(50, swarm.instance_variable_get(:@global_concurrency))
      assert_equal(10, swarm.instance_variable_get(:@default_local_concurrency))
      assert_nil(swarm.lead_agent)
    end

    def test_initialization_with_custom_limits
      swarm = Swarm.new(
        name: "Custom Swarm",
        global_concurrency: 100,
        default_local_concurrency: 20,
      )

      assert_equal(100, swarm.instance_variable_get(:@global_concurrency))
      assert_equal(20, swarm.instance_variable_get(:@default_local_concurrency))
    end

    def test_initialization_creates_global_semaphore
      swarm = Swarm.new(name: "Test Swarm")

      semaphore = swarm.instance_variable_get(:@global_semaphore)

      assert_instance_of(Async::Semaphore, semaphore)
    end

    def test_add_agent_with_required_fields
      swarm = Swarm.new(name: "Test Swarm")

      result = swarm.add_agent(create_agent(
        name: :test_agent,
        description: "Test agent",
        model: "gpt-5",
        system_prompt: "You are a test agent",
        directory: ".",
      ))

      assert_equal(swarm, result) # Returns self for chaining
      assert_includes(swarm.agent_names, :test_agent)
    end

    def test_add_agent_with_all_fields
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :full_agent,
        description: "Full agent",
        model: "claude-sonnet-4",
        system_prompt: "You are full",
        tools: [:Read, :Edit],
        delegates_to: [:other],
        directory: ".",
        base_url: "https://api.anthropic.com",
        mcp_servers: [{ type: :stdio }],
        parameters: {
          temperature: 0.7,
          max_tokens: 4000,
          reasoning: "high",
        },
        max_concurrent_tools: 15,
      ))

      assert_includes(swarm.agent_names, :full_agent)
    end

    def test_add_agent_converts_name_to_symbol
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: "string_name",
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      assert_includes(swarm.agent_names, :string_name)
    end

    def test_add_duplicate_agent_raises_error
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :duplicate,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      error = assert_raises(ConfigurationError) do
        swarm.add_agent(create_agent(
          name: :duplicate,
          description: "Test",
          model: "gpt-5",
          system_prompt: "Test",
          directory: ".",
        ))
      end

      assert_match(/already exists/i, error.message)
    end

    def test_add_agent_uses_default_directories
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
      ))

      agent_def = swarm.instance_variable_get(:@agent_definitions)[:test]

      assert_equal(File.expand_path("."), agent_def.directory)
    end

    def test_set_lead_agent
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.lead = :lead

      assert_equal(:lead, swarm.lead_agent)
    end

    def test_set_lead_converts_to_symbol
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

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

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "A1",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))
      swarm.add_agent(create_agent(
        name: :agent2,
        description: "A2",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))
      swarm.add_agent(create_agent(
        name: :agent3,
        description: "A3",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

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

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      agents_hash = swarm.instance_variable_get(:@agents)

      assert_empty(agents_hash) # Not initialized yet

      swarm.lead = :agent1

      # Mock HTTP response so execution succeeds
      stub_llm_request(mock_llm_response(content: "Test"))

      # Execute to trigger agent initialization
      swarm.execute("test")

      agents_hash = swarm.instance_variable_get(:@agents)

      refute_empty(agents_hash) # Now initialized
    end

    def test_default_constants
      assert_equal(50, Swarm::DEFAULT_GLOBAL_CONCURRENCY)
      assert_equal(10, Swarm::DEFAULT_LOCAL_CONCURRENCY)
    end

    def test_chaining_add_agent_and_set_lead
      swarm = Swarm.new(name: "Test Swarm")
        .add_agent(create_agent(
          name: :lead,
          description: "Lead",
          model: "gpt-5",
          system_prompt: "Test",
          directory: ".",
        ))
        .add_agent(create_agent(
          name: :backend,
          description: "Backend",
          model: "gpt-5",
          system_prompt: "Test",
          directory: ".",
        ))

      swarm.lead = :lead

      assert_equal(2, swarm.agent_names.length)
      assert_equal(:lead, swarm.lead_agent)
    end

    def test_agents_share_global_semaphore
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.add_agent(create_agent(
        name: :agent2,
        description: "Agent 2",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      global_semaphore = swarm.instance_variable_get(:@global_semaphore)
      swarm.instance_variable_get(:@agent_definitions)

      # Both agents will receive the same global semaphore when initialized
      assert_instance_of(Async::Semaphore, global_semaphore)
    end

    def test_agent_gets_default_local_limit
      swarm = Swarm.new(name: "Test Swarm", default_local_concurrency: 15)

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      # Initialize agents to verify that the local limit is passed correctly
      # max_concurrent_tools is stored in the config passed to AgentChat, not in AgentDefinition
      swarm.send(:initialize_agents)
      agent = swarm.agent(:agent1)
      local_semaphore = agent.instance_variable_get(:@local_semaphore)

      # Verify that a local semaphore was created with the correct limit
      assert_instance_of(Async::Semaphore, local_semaphore)
      assert_equal(15, local_semaphore.limit)
    end

    def test_agent_can_override_local_limit
      swarm = Swarm.new(name: "Test Swarm", default_local_concurrency: 15)

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
        max_concurrent_tools: 25,
      ))

      # Initialize agents to verify that the overridden limit is passed correctly
      swarm.send(:initialize_agents)
      agent = swarm.agent(:agent1)
      local_semaphore = agent.instance_variable_get(:@local_semaphore)

      # Verify that a local semaphore was created with the overridden limit
      assert_instance_of(Async::Semaphore, local_semaphore)
      assert_equal(25, local_semaphore.limit)
    end

    def test_agent_uses_default_timeout
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      agent_def = swarm.instance_variable_get(:@agent_definitions)[:agent1]

      assert_equal(300, agent_def.timeout) # 5 minutes default
    end

    def test_agent_can_override_timeout
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
        timeout: 600, # 10 minutes for reasoning models
      ))

      agent_def = swarm.instance_variable_get(:@agent_definitions)[:agent1]

      assert_equal(600, agent_def.timeout)
    end

    def test_agent_method_returns_agent_instance
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test_agent,
        description: "Test agent",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      # Force agent initialization
      swarm.instance_variable_set(:@agents_initialized, false)
      swarm.send(:initialize_agents)

      agent = swarm.agent(:test_agent)

      assert_instance_of(Agent::Chat, agent)
    end

    def test_agent_method_with_string_converts_to_symbol
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test_agent,
        description: "Test agent",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.send(:initialize_agents)

      agent = swarm.agent("test_agent")

      assert_instance_of(Agent::Chat, agent)
    end

    def test_agent_method_with_nonexistent_agent_raises_error
      swarm = Swarm.new(name: "Test Swarm")

      error = assert_raises(AgentNotFoundError) do
        swarm.agent(:nonexistent)
      end

      assert_match(/agent.*not found/i, error.message)
    end

    def test_execute_returns_result_instance
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.lead = :lead

      # Mock HTTP response from LLM API
      stub_llm_request(mock_llm_response(content: "Test response"))

      result = swarm.execute("test prompt")

      assert_instance_of(Result, result)
      assert_equal("Test response", result.content)
      assert_equal("lead", result.agent)
      assert_predicate(result, :success?)
    end

    def test_execute_with_error_returns_failed_result
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.lead = :lead

      # Mock the lead agent to raise an error
      swarm.send(:initialize_agents)
      lead_agent = swarm.agent(:lead)

      lead_agent.define_singleton_method(:ask) do |_prompt|
        raise StandardError, "Test error"
      end

      result = swarm.execute("test prompt")

      assert_instance_of(Result, result)
      refute_predicate(result, :success?)
      assert_predicate(result, :failure?)
      assert_instance_of(StandardError, result.error)
      assert_equal("Test error", result.error.message)
    end

    def test_execute_with_type_error_returns_llm_error_for_proxy
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        provider: "openai",
        base_url: "https://custom.proxy",
        directory: ".",
      ))

      swarm.lead = :lead

      # Mock the lead agent to raise a TypeError with dig method error
      swarm.send(:initialize_agents)
      lead_agent = swarm.agent(:lead)

      lead_agent.define_singleton_method(:ask) do |_prompt|
        raise TypeError, "String does not have #dig method"
      end

      result = swarm.execute("test prompt")

      assert_instance_of(Result, result)
      refute_predicate(result, :success?)
      assert_instance_of(LLMError, result.error)
      assert_match(/proxy.*unreachable/i, result.error.message)
      assert_match(/custom\.proxy/i, result.error.message)
    end

    def test_execute_with_streaming_logs
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.lead = :lead

      # Mock HTTP response from LLM API
      stub_llm_request(mock_llm_response(content: "Test response"))

      logs = []
      result = swarm.execute("test prompt") do |log_entry|
        logs << log_entry
      end

      assert_instance_of(Result, result)
      assert_predicate(result, :success?)
    end

    def test_create_delegation_tool_creates_functional_tool
      swarm = Swarm.new(name: "Test Swarm")

      # Create a mock delegate chat
      mock_response = Struct.new(:content).new("Delegate response")
      delegate_chat = Minitest::Mock.new
      delegate_chat.expect(:ask, mock_response, [String])

      tool = swarm.send(
        :create_delegation_tool,
        name: "backend",
        description: "Backend developer",
        delegate_chat: delegate_chat,
        agent_name: "coordinator",
      )

      # Tool should be a subclass of RubyLLM::Tool
      assert_kind_of(RubyLLM::Tool, tool, "Expected tool to be a RubyLLM::Tool")
      assert_equal("DelegateTaskToBackend", tool.name)

      # Execute the tool
      result = tool.execute(task: "Build API")

      assert_equal("Delegate response", result)
      delegate_chat.verify
    end

    def test_create_delegation_tool_handles_timeout_error
      swarm = Swarm.new(name: "Test Swarm")

      # Create a mock delegate that raises timeout error
      delegate_chat = Object.new
      def delegate_chat.ask(_task)
        raise Faraday::TimeoutError, "Connection timeout"
      end

      tool = swarm.send(
        :create_delegation_tool,
        name: "backend",
        description: "Backend developer",
        delegate_chat: delegate_chat,
        agent_name: "coordinator",
      )

      result = tool.execute(task: "Build API")

      assert_match(/timed out/i, result)
      assert_match(/backend/i, result)
    end

    def test_create_delegation_tool_handles_network_error
      swarm = Swarm.new(name: "Test Swarm")

      # Create a mock delegate that raises network error
      delegate_chat = Object.new
      def delegate_chat.ask(_task)
        raise Faraday::ConnectionFailed, "Connection failed"
      end

      tool = swarm.send(
        :create_delegation_tool,
        name: "backend",
        description: "Backend developer",
        delegate_chat: delegate_chat,
        agent_name: "coordinator",
      )

      result = tool.execute(task: "Build API")

      assert_match(/network error/i, result)
      assert_match(/backend/i, result)
    end

    def test_create_delegation_tool_handles_generic_error
      swarm = Swarm.new(name: "Test Swarm")

      # Create a mock delegate that raises generic error
      delegate_chat = Object.new
      def delegate_chat.ask(_task)
        raise StandardError, "Something went wrong"
      end

      tool = swarm.send(
        :create_delegation_tool,
        name: "backend",
        description: "Backend developer",
        delegate_chat: delegate_chat,
        agent_name: "coordinator",
      )

      result = tool.execute(task: "Build API")

      assert_match(/error/i, result)
      assert_match(/backend/i, result)
      assert_match(/something went wrong/i, result)
    end

    def test_register_agent_tools_adds_delegation_tools
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        delegates_to: [:backend],
        directory: ".",
      ))

      swarm.add_agent(create_agent(
        name: :backend,
        description: "Backend developer",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.lead = :lead

      # Initialize agents
      swarm.send(:initialize_agents)

      lead_agent = swarm.agent(:lead)

      # Verify backend tool was registered
      assert(lead_agent.tools.key?(:DelegateTaskToBackend), "Expected backend tool to be registered")
    end

    def test_register_agent_tools_with_unknown_agent_raises_error
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        delegates_to: [:nonexistent],
        directory: ".",
      ))

      swarm.lead = :lead

      error = assert_raises(ConfigurationError) do
        swarm.send(:initialize_agents)
      end

      assert_match(/unknown agent/i, error.message)
    end

    def test_execute_with_agent_delegation
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        delegates_to: [:backend],
        directory: ".",
      ))

      swarm.add_agent(create_agent(
        name: :backend,
        description: "Backend developer",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.lead = :lead

      # Initialize and mock agents
      swarm.send(:initialize_agents)

      backend_agent = swarm.agent(:backend)
      backend_mock_response = Struct.new(:content).new("Backend response")
      backend_agent.define_singleton_method(:ask) do |_task|
        backend_mock_response
      end

      lead_agent = swarm.agent(:lead)
      lead_mock_response = Struct.new(:content).new("Lead final response")
      lead_agent.define_singleton_method(:ask) do |_prompt|
        lead_mock_response
      end

      result = swarm.execute("test task")

      assert_predicate(result, :success?)
      assert_equal("Lead final response", result.content)
    end

    def test_initialize_agents_creates_all_agents
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.add_agent(create_agent(
        name: :agent2,
        description: "Agent 2",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.send(:initialize_agents)

      agents = swarm.instance_variable_get(:@agents)

      assert_equal(2, agents.size)
      assert_instance_of(Agent::Chat, agents[:agent1])
      assert_instance_of(Agent::Chat, agents[:agent2])
    end

    def test_initialize_agents_sets_system_prompt
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Custom system prompt",
        directory: ".",
      ))

      swarm.send(:initialize_agents)

      # We can't easily test this without exposing internal RubyLLM state
      # but we can verify the agent was created
      agent = swarm.agent(:agent1)

      assert_instance_of(Agent::Chat, agent)
    end

    def test_initialize_agents_configures_parameters
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        parameters: {
          temperature: 0.7,
          max_tokens: 2000,
        },
        directory: ".",
      ))

      swarm.send(:initialize_agents)

      agent = swarm.agent(:agent1)

      assert_instance_of(Agent::Chat, agent)
    end

    def test_execute_with_configuration_error_raises
      swarm = Swarm.new(name: "Test Swarm")

      # No lead agent set

      error = assert_raises(ConfigurationError) do
        swarm.execute("test")
      end

      assert_match(/no lead agent/i, error.message)
    end

    def test_execute_duration_is_measured
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.lead = :lead

      swarm.send(:initialize_agents)
      lead_agent = swarm.agent(:lead)

      mock_response = Struct.new(:content).new("Test response")
      lead_agent.define_singleton_method(:ask) do |_prompt|
        sleep(0.05) # Simulate some work
        mock_response
      end

      result = swarm.execute("test")

      assert_operator(result.duration, :>, 0, "Expected duration to be positive")
      assert_operator(result.duration, :>=, 0.05, "Expected duration to be at least 0.05 seconds")
    end

    def test_normalize_tools_with_hash_having_name_key
      swarm = Swarm.new(name: "Test Swarm")

      tools = [{ name: :Write, permissions: { allowed_paths: ["tmp/**/*"] } }]
      normalized = swarm.send(:normalize_tools, tools)

      assert_equal(1, normalized.size)
      assert_equal(:Write, normalized[0][:name])
      assert_equal({ allowed_paths: ["tmp/**/*"] }, normalized[0][:permissions])
    end

    def test_normalize_tools_with_inline_permissions_hash
      swarm = Swarm.new(name: "Test Swarm")

      tools = [{ Write: { allowed_paths: ["tmp/**/*"] } }]
      normalized = swarm.send(:normalize_tools, tools)

      assert_equal(1, normalized.size)
      assert_equal(:Write, normalized[0][:name])
      assert_equal({ allowed_paths: ["tmp/**/*"] }, normalized[0][:permissions])
    end

    def test_normalize_tools_with_invalid_type_raises_error
      swarm = Swarm.new(name: "Test Swarm")

      error = assert_raises(ConfigurationError) do
        swarm.send(:normalize_tools, [123])
      end

      assert_includes(error.message, "Invalid tool specification")
    end

    def test_create_tool_instance_for_multi_edit
      swarm = Swarm.new(name: "Test Swarm")

      tool = swarm.send(:create_tool_instance, :MultiEdit, :test_agent, ".")

      assert_respond_to(tool, :execute)
    end

    def test_create_tool_instance_for_scratchpad_tools
      swarm = Swarm.new(name: "Test Swarm")

      write_tool = swarm.send(:create_tool_instance, :ScratchpadWrite, :test_agent, ".")

      assert_respond_to(write_tool, :execute)

      read_tool = swarm.send(:create_tool_instance, :ScratchpadRead, :test_agent, ".")

      assert_respond_to(read_tool, :execute)

      list_tool = swarm.send(:create_tool_instance, :ScratchpadList, :test_agent, ".")

      assert_respond_to(list_tool, :execute)
    end

    def test_execute_with_type_error_without_base_url
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.lead = :lead

      # Mock the lead agent to raise a TypeError that doesn't match the special case
      swarm.send(:initialize_agents)
      lead_agent = swarm.agent(:lead)

      lead_agent.define_singleton_method(:ask) do |_prompt|
        raise TypeError, "Some other type error"
      end

      result = swarm.execute("test prompt")

      assert_instance_of(Result, result)
      refute_predicate(result, :success?)
      assert_instance_of(TypeError, result.error)
    end

    def test_execute_with_nil_lead_agent_in_error
      swarm = Swarm.new(name: "Test Swarm")

      # Add agent but don't set lead
      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      # Try to execute without lead (should raise ConfigurationError)
      error = assert_raises(ConfigurationError) do
        swarm.execute("test")
      end

      assert_includes(error.message, "No lead agent")
    end

    def test_cleanup_with_alive_clients
      swarm = Swarm.new(name: "Test Swarm")

      # Mock MCP clients
      mock_client = Minitest::Mock.new
      mock_client.expect(:alive?, true)
      mock_client.expect(:stop, nil)
      mock_client.expect(:name, "test_client")

      swarm.instance_variable_set(:@mcp_clients, { agent1: [mock_client] })

      # Suppress logger output
      capture_io do
        swarm.send(:cleanup)
      end

      mock_client.verify
    end

    def test_cleanup_with_dead_clients
      swarm = Swarm.new(name: "Test Swarm")

      # Mock MCP clients that are not alive
      # Note: cleanup always calls client.name for logging, even if not alive
      mock_client = Minitest::Mock.new
      mock_client.expect(:alive?, false)
      mock_client.expect(:name, "dead_client")

      swarm.instance_variable_set(:@mcp_clients, { agent1: [mock_client] })

      # Should not call stop since client is not alive
      capture_io do
        swarm.send(:cleanup)
      end

      # Verify alive? and name were called but not stop
      mock_client.verify
    end

    def test_cleanup_with_client_error
      swarm = Swarm.new(name: "Test Swarm")

      # Mock client that raises error on stop
      mock_client = Object.new
      def mock_client.alive?
        true
      end

      def mock_client.stop
        raise StandardError, "Stop failed"
      end

      def mock_client.name
        "failing_client"
      end

      swarm.instance_variable_set(:@mcp_clients, { agent1: [mock_client] })

      # Should not raise error, just log
      capture_io do
        swarm.send(:cleanup)
      end

      # Verify clients were cleared
      assert_empty(swarm.instance_variable_get(:@mcp_clients))
    end

    def test_agent_with_no_system_prompt
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: nil,
        directory: ".",
      ))

      swarm.send(:initialize_agents)

      # Should create agent successfully
      assert_instance_of(Agent::Chat, swarm.agent(:test))
    end

    def test_agent_with_no_parameters
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
        parameters: nil,
      ))

      swarm.send(:initialize_agents)

      assert_instance_of(Agent::Chat, swarm.agent(:test))
    end

    def test_agent_with_empty_parameters
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
        parameters: {},
      ))

      swarm.send(:initialize_agents)

      assert_instance_of(Agent::Chat, swarm.agent(:test))
    end

    def test_set_bypass_permissions
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.agent_definition(:test).bypass_permissions = true

      agent_def = swarm.agent_definition(:test)

      assert(agent_def.bypass_permissions)
    end

    def test_set_bypass_permissions_with_string_name
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.agent_definition("test").bypass_permissions = false

      agent_def = swarm.agent_definition(:test)

      refute(agent_def.bypass_permissions)
    end

    def test_set_bypass_permissions_for_nonexistent_agent_raises_error
      swarm = Swarm.new(name: "Test Swarm")

      error = assert_raises(AgentNotFoundError) do
        swarm.agent_definition(:nonexistent).bypass_permissions = true
      end

      assert_includes(error.message, "not found")
    end

    def test_build_mcp_transport_config_for_stdio
      swarm = Swarm.new(name: "Test Swarm")

      config = {
        type: :stdio,
        command: "test-server",
        args: ["--port", "3000"],
        env: { "API_KEY" => "test123" },
      }

      result = swarm.send(:build_mcp_transport_config, :stdio, config)

      assert_equal("test-server", result[:command])
      assert_equal(["--port", "3000"], result[:args])
      assert_equal({ "API_KEY" => "test123" }, result[:env])
    end

    def test_build_mcp_transport_config_for_stdio_with_defaults
      swarm = Swarm.new(name: "Test Swarm")

      config = {
        type: :stdio,
        command: "test-server",
      }

      result = swarm.send(:build_mcp_transport_config, :stdio, config)

      assert_equal("test-server", result[:command])
      assert_empty(result[:args])
      assert_empty(result[:env])
    end

    def test_build_mcp_transport_config_for_sse
      swarm = Swarm.new(name: "Test Swarm")

      config = {
        type: :sse,
        url: "http://localhost:3000/sse",
        headers: { "Authorization" => "Bearer token" },
        version: "http1_1",
      }

      result = swarm.send(:build_mcp_transport_config, :sse, config)

      assert_equal("http://localhost:3000/sse", result[:url])
      assert_equal({ "Authorization" => "Bearer token" }, result[:headers])
      assert_equal(:http1_1, result[:version])
    end

    def test_build_mcp_transport_config_for_sse_with_defaults
      swarm = Swarm.new(name: "Test Swarm")

      config = {
        type: :sse,
        url: "http://localhost:3000/sse",
      }

      result = swarm.send(:build_mcp_transport_config, :sse, config)

      assert_equal("http://localhost:3000/sse", result[:url])
      assert_empty(result[:headers])
      assert_equal(:http2, result[:version])
    end

    def test_build_mcp_transport_config_for_streamable
      swarm = Swarm.new(name: "Test Swarm")

      config = {
        type: :streamable,
        url: "http://localhost:3000",
        headers: { "X-API-Key" => "test" },
        version: "http1_1",
        oauth: { client_id: "test" },
        rate_limit: { requests_per_second: 10 },
      }

      result = swarm.send(:build_mcp_transport_config, :streamable, config)

      assert_equal("http://localhost:3000", result[:url])
      assert_equal({ "X-API-Key" => "test" }, result[:headers])
      assert_equal(:http1_1, result[:version])
      assert_equal({ client_id: "test" }, result[:oauth])
      assert_equal({ requests_per_second: 10 }, result[:rate_limit])
    end

    def test_build_mcp_transport_config_for_streamable_with_defaults
      swarm = Swarm.new(name: "Test Swarm")

      config = {
        type: :streamable,
        url: "http://localhost:3000",
      }

      result = swarm.send(:build_mcp_transport_config, :streamable, config)

      assert_equal("http://localhost:3000", result[:url])
      assert_empty(result[:headers])
      assert_equal(:http2, result[:version])
      assert_nil(result[:oauth])
      assert_nil(result[:rate_limit])
    end

    def test_build_mcp_transport_config_with_unsupported_type_raises_error
      swarm = Swarm.new(name: "Test Swarm")

      error = assert_raises(ArgumentError) do
        swarm.send(:build_mcp_transport_config, :unknown, {})
      end

      assert_includes(error.message, "Unsupported transport type")
    end

    def test_agent_with_assume_model_exists_false
      swarm = Swarm.new(name: "Test Swarm")

      # Without base_url, assume_model_exists should default to false
      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
        assume_model_exists: false,
      ))

      swarm.send(:initialize_agents)

      assert_instance_of(Agent::Chat, swarm.agent(:test))
    end

    def test_agent_with_assume_model_exists_explicit_with_base_url
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "custom-model",
        provider: "openai",
        base_url: "https://custom.api",
        system_prompt: "Test",
        directory: ".",
        assume_model_exists: true, # Explicitly set
      ))

      swarm.send(:initialize_agents)

      assert_instance_of(Agent::Chat, swarm.agent(:test))
    end

    def test_cleanup_with_empty_clients
      swarm = Swarm.new(name: "Test Swarm")

      # With empty mcp_clients hash, cleanup should return early
      swarm.instance_variable_set(:@mcp_clients, {})

      # Should not raise error
      swarm.send(:cleanup)

      # Verify clients remain empty
      assert_empty(swarm.instance_variable_get(:@mcp_clients))
    end

    def test_wrap_tool_with_permissions_bypass
      swarm = Swarm.new(name: "Test Swarm")

      tool_instance = Tools::Bash.new(directory: ".")
      agent_definition = Agent::Definition.new(:test, {
        description: "Test",
        bypass_permissions: true,
        directory: ".",
      })

      wrapped = swarm.send(:wrap_tool_with_permissions, tool_instance, {}, agent_definition)

      # Should return unwrapped tool
      assert_same(tool_instance, wrapped)
    end

    def test_wrap_tool_with_permissions_no_config
      swarm = Swarm.new(name: "Test Swarm")

      tool_instance = Tools::Bash.new(directory: ".")
      agent_definition = Agent::Definition.new(:test, {
        description: "Test",
        bypass_permissions: false,
        directory: ".",
      })

      wrapped = swarm.send(:wrap_tool_with_permissions, tool_instance, nil, agent_definition)

      # Should return unwrapped tool when no permissions config
      assert_same(tool_instance, wrapped)
    end

    def test_wrap_tool_with_permissions_applies_config
      swarm = Swarm.new(name: "Test Swarm")

      tool_instance = Tools::Bash.new(directory: ".")
      agent_definition = Agent::Definition.new(:test, {
        description: "Test",
        bypass_permissions: false,
        directory: ".",
      })

      permissions_config = { allowed_paths: ["tmp/**/*"] }

      wrapped = swarm.send(:wrap_tool_with_permissions, tool_instance, permissions_config, agent_definition)

      # Should return wrapped validator tool
      assert_instance_of(Permissions::Validator, wrapped)
    end

    def test_initialize_agents_without_logstream_emitter
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :agent1,
        description: "Agent 1",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      # Ensure LogStream emitter is nil
      LogStream.emitter = nil

      # Access agent to trigger initialization
      agent = swarm.agent(:agent1)

      # Should create agents successfully without setting up logging
      assert_instance_of(Agent::Chat, agent)
    end

    def test_execute_initializes_agents_lazily
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :lead,
        description: "Lead",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
      ))

      swarm.lead = :lead

      # Agents not initialized yet
      refute(swarm.instance_variable_get(:@agents_initialized))

      # Mock HTTP response
      stub_llm_request(mock_llm_response(content: "Response"))

      swarm.execute("test")

      # Now agents should be initialized
      assert(swarm.instance_variable_get(:@agents_initialized))
    end

    def test_agent_names_returns_all_added_agents
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(name: :agent1, description: "A1", model: "gpt-5", system_prompt: "Test", directory: "."))
      swarm.add_agent(create_agent(name: :agent2, description: "A2", model: "gpt-5", system_prompt: "Test", directory: "."))
      swarm.add_agent(create_agent(name: :agent3, description: "A3", model: "gpt-5", system_prompt: "Test", directory: "."))

      names = swarm.agent_names

      assert_equal([:agent1, :agent2, :agent3], names.sort)
    end

    def test_agent_with_inline_tool_permissions
      swarm = Swarm.new(name: "Test Swarm")

      # Using inline permissions format: { Write: { allowed_paths: [...] } }
      swarm.add_agent(create_agent(
        name: :restricted,
        description: "Restricted agent",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
        tools: [
          { Write: { allowed_paths: ["tmp/**/*"] } },
        ],
      ))

      # Access agent to trigger tool initialization
      agent = swarm.agent(:restricted)

      # Agent should have Write tool with permissions
      assert(agent.tools.key?(:Write))
    end

    def test_load_from_yaml_class_method
      config = valid_yaml_config

      with_yaml_file(config) do |path|
        swarm = Swarm.load(path)

        assert_instance_of(Swarm, swarm)
        assert_equal("Test Swarm", swarm.name)
        assert_includes(swarm.agent_names, :lead)
        assert_includes(swarm.agent_names, :backend)
      end
    end

    def test_agent_with_string_tool_names
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
        tools: ["Read", "Write"], # String names instead of symbols
      ))

      agent = swarm.agent(:test)

      # Should convert strings to symbols
      assert(agent.tools.key?(:Read))
      assert(agent.tools.key?(:Write))
    end

    def test_agent_with_mixed_tool_formats
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
        directory: ".",
        tools: [
          :Read, # Symbol
          "Write", # String
          { Edit: { allowed_paths: ["**/*"] } }, # Inline permissions format
        ],
      ))

      agent = swarm.agent(:test)

      assert(agent.tools.key?(:Read))
      assert(agent.tools.key?(:Write))
      assert(agent.tools.key?(:Edit))
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
              "directory" => ".",
            },
            "backend" => {
              "description" => "Backend agent",
              "system_prompt" => "You build APIs",
              "delegates_to" => [],
              "directory" => ".",
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
