# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class AgentRegistryTest < Minitest::Test
    def setup
      @registry = AgentRegistry.new
      @mock_agent = create_mock_agent(:test_agent)
    end

    def test_initialization
      registry = AgentRegistry.new

      assert_instance_of(AgentRegistry, registry)
      assert_equal(0, registry.count)
    end

    def test_register_agent
      @registry.register(@mock_agent)

      assert_equal(1, @registry.count)
      assert(@registry.exists?(:test_agent))
    end

    def test_register_multiple_agents
      agent1 = create_mock_agent(:agent1)
      agent2 = create_mock_agent(:agent2)
      agent3 = create_mock_agent(:agent3)

      @registry.register(agent1)
      @registry.register(agent2)
      @registry.register(agent3)

      assert_equal(3, @registry.count)
      assert(@registry.exists?(:agent1))
      assert(@registry.exists?(:agent2))
      assert(@registry.exists?(:agent3))
    end

    def test_register_duplicate_agent_raises_error
      @registry.register(@mock_agent)

      error = assert_raises(ConfigurationError) do
        @registry.register(@mock_agent)
      end

      assert_match(/already registered/i, error.message)
      assert_match(/test_agent/, error.message)
    end

    def test_get_existing_agent
      @registry.register(@mock_agent)

      agent = @registry.get(:test_agent)

      assert_equal(@mock_agent, agent)
    end

    def test_get_nonexistent_agent_raises_error
      error = assert_raises(AgentNotFoundError) do
        @registry.get(:nonexistent)
      end

      assert_match(/not found/i, error.message)
      assert_match(/nonexistent/, error.message)
    end

    def test_exists_returns_true_for_existing_agent
      @registry.register(@mock_agent)

      assert(@registry.exists?(:test_agent))
    end

    def test_exists_returns_false_for_nonexistent_agent
      refute(@registry.exists?(:nonexistent))
    end

    def test_all_returns_empty_array_initially
      assert_empty(@registry.all)
    end

    def test_all_returns_all_registered_agents
      agent1 = create_mock_agent(:agent1)
      agent2 = create_mock_agent(:agent2)

      @registry.register(agent1)
      @registry.register(agent2)

      all_agents = @registry.all

      assert_equal(2, all_agents.length)
      assert_includes(all_agents, agent1)
      assert_includes(all_agents, agent2)
    end

    def test_count_returns_zero_initially
      assert_equal(0, @registry.count)
    end

    def test_count_returns_correct_number
      @registry.register(create_mock_agent(:agent1))

      assert_equal(1, @registry.count)

      @registry.register(create_mock_agent(:agent2))

      assert_equal(2, @registry.count)

      @registry.register(create_mock_agent(:agent3))

      assert_equal(3, @registry.count)
    end

    def test_names_returns_empty_array_initially
      assert_empty(@registry.names)
    end

    def test_names_returns_all_agent_names
      @registry.register(create_mock_agent(:agent1))
      @registry.register(create_mock_agent(:agent2))
      @registry.register(create_mock_agent(:agent3))

      names = @registry.names

      assert_equal(3, names.length)
      assert_includes(names, :agent1)
      assert_includes(names, :agent2)
      assert_includes(names, :agent3)
    end

    def test_clear_removes_all_agents
      @registry.register(create_mock_agent(:agent1))
      @registry.register(create_mock_agent(:agent2))

      assert_equal(2, @registry.count)

      @registry.clear

      assert_equal(0, @registry.count)
      assert_empty(@registry.all)
      assert_empty(@registry.names)
    end

    def test_uses_regular_hash_not_concurrent
      # Verify implementation uses regular Hash (for fiber-safety)
      agents_hash = @registry.instance_variable_get(:@agents)

      assert_instance_of(Hash, agents_hash)
      refute_kind_of(Concurrent::Hash, agents_hash) if defined?(Concurrent::Hash)
    end

    def test_fiber_safe_concurrent_access
      # Test that registry works correctly with concurrent fiber access
      agents = 10.times.map { |i| create_mock_agent("agent#{i}".to_sym) }

      Async do
        agents.map do |agent|
          Async do
            @registry.register(agent)
          end
        end.each(&:wait)
      end.wait

      assert_equal(10, @registry.count)
      agents.each do |agent|
        assert(@registry.exists?(agent.name))
      end
    end

    private

    def create_mock_agent(name)
      agent = Object.new
      agent.define_singleton_method(:name) { name }
      agent
    end
  end
end
