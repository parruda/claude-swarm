# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class AllAgentsProviderConfigTest < Minitest::Test
    def test_all_agents_model_inherited_by_agents
      swarm = SwarmSDK.build do
        name("Model Inheritance Test")
        lead(:agent1)

        all_agents do
          model("gpt-4o")
        end

        agent(:agent1) do
          description("Agent 1")
          # No model specified - should inherit from all_agents
        end

        agent(:agent2) do
          description("Agent 2")
          # No model specified - should inherit from all_agents
        end
      end

      agent1_def = swarm.agent_definition(:agent1)
      agent2_def = swarm.agent_definition(:agent2)

      assert_equal("gpt-4o", agent1_def.model)
      assert_equal("gpt-4o", agent2_def.model)
    end

    def test_agent_model_overrides_all_agents
      swarm = SwarmSDK.build do
        name("Model Override Test")
        lead(:agent1)

        all_agents do
          model("gpt-4o")
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4o-mini") # Override all_agents
        end

        agent(:agent2) do
          description("Agent 2")
          # Inherit from all_agents
        end
      end

      agent1_def = swarm.agent_definition(:agent1)
      agent2_def = swarm.agent_definition(:agent2)

      assert_equal("gpt-4o-mini", agent1_def.model) # Overridden
      assert_equal("gpt-4o", agent2_def.model) # Inherited
    end

    def test_all_agents_provider_inherited
      swarm = SwarmSDK.build do
        name("Provider Inheritance Test")
        lead(:agent1)

        all_agents do
          provider(:anthropic)
        end

        agent(:agent1) do
          description("Agent 1")
          model("claude-3-5-sonnet-20241022")
        end
      end

      agent1_def = swarm.agent_definition(:agent1)

      assert_equal(:anthropic, agent1_def.provider)
    end

    def test_all_agents_base_url_inherited
      swarm = SwarmSDK.build do
        name("Base URL Inheritance Test")
        lead(:agent1)

        all_agents do
          provider(:openai)
          base_url("http://proxy.example.com/v1")
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4")
        end

        agent(:agent2) do
          description("Agent 2")
          model("gpt-4")
          base_url("http://other-proxy.com/v1") # Override
        end
      end

      agent1_def = swarm.agent_definition(:agent1)
      agent2_def = swarm.agent_definition(:agent2)

      assert_equal("http://proxy.example.com/v1", agent1_def.base_url) # Inherited
      assert_equal("http://other-proxy.com/v1", agent2_def.base_url) # Overridden
    end

    def test_all_agents_timeout_inherited
      swarm = SwarmSDK.build do
        name("Timeout Inheritance Test")
        lead(:agent1)

        all_agents do
          timeout(180)
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4")
        end

        agent(:agent2) do
          description("Agent 2")
          model("gpt-4")
          timeout(60) # Override
        end
      end

      agent1_def = swarm.agent_definition(:agent1)
      agent2_def = swarm.agent_definition(:agent2)

      assert_equal(180, agent1_def.timeout) # Inherited
      assert_equal(60, agent2_def.timeout) # Overridden
    end

    def test_all_agents_parameters_merged
      swarm = SwarmSDK.build do
        name("Parameters Merge Test")
        lead(:agent1)

        all_agents do
          parameters({ temperature: 0.7, max_tokens: 1000 })
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4")
          # No parameters - should inherit all_agents
        end

        agent(:agent2) do
          description("Agent 2")
          model("gpt-4")
          parameters({ max_tokens: 2000, top_p: 0.9 }) # Merge with all_agents
        end
      end

      agent1_def = swarm.agent_definition(:agent1)
      agent2_def = swarm.agent_definition(:agent2)

      # Agent1: inherits all_agents parameters
      assert_in_delta(0.7, agent1_def.parameters[:temperature])
      assert_equal(1000, agent1_def.parameters[:max_tokens])

      # Agent2: merged (agent values override)
      assert_in_delta(0.7, agent2_def.parameters[:temperature]) # From all_agents
      assert_equal(2000, agent2_def.parameters[:max_tokens]) # Overridden by agent
      assert_in_delta(0.9, agent2_def.parameters[:top_p]) # From agent
    end

    def test_all_agents_headers_merged
      swarm = SwarmSDK.build do
        name("Headers Merge Test")
        lead(:agent1)

        all_agents do
          headers({ "X-Custom-Header" => "value1", "X-Shared" => "shared" })
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4")
          # No headers - should inherit all_agents
        end

        agent(:agent2) do
          description("Agent 2")
          model("gpt-4")
          headers({ "X-Shared" => "overridden", "X-Agent-Header" => "agent-value" })
        end
      end

      agent1_def = swarm.agent_definition(:agent1)
      agent2_def = swarm.agent_definition(:agent2)

      # Agent1: inherits all_agents headers
      assert_equal("value1", agent1_def.headers["X-Custom-Header"])
      assert_equal("shared", agent1_def.headers["X-Shared"])

      # Agent2: merged (agent values override)
      assert_equal("value1", agent2_def.headers["X-Custom-Header"]) # From all_agents
      assert_equal("overridden", agent2_def.headers["X-Shared"]) # Overridden
      assert_equal("agent-value", agent2_def.headers["X-Agent-Header"]) # From agent
    end

    def test_all_agents_coding_agent_inherited
      swarm = SwarmSDK.build do
        name("Coding Agent Test")
        lead(:agent1)

        all_agents do
          coding_agent(true)
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4")
          # Should inherit coding_agent: true
        end

        agent(:agent2) do
          description("Agent 2")
          model("gpt-4")
          coding_agent(false) # Override
        end
      end

      agent1_def = swarm.agent_definition(:agent1)
      agent2_def = swarm.agent_definition(:agent2)

      assert(agent1_def.coding_agent) # Inherited
      refute(agent2_def.coding_agent) # Overridden
    end

    def test_all_agents_combined_config
      # Test all fields together
      swarm = SwarmSDK.build do
        name("Combined Config Test")
        lead(:backend)

        all_agents do
          model("gpt-4o")
          provider(:openai)
          base_url("http://proxy.com/v1")
          timeout(180)
          parameters({ temperature: 0.7 })
          headers({ "X-Common" => "value" })
          coding_agent(false)
          tools(:Read, :Write)
        end

        agent(:backend) do
          description("Backend dev")
          # Inherits everything from all_agents
        end

        agent(:frontend) do
          description("Frontend dev")
          model("gpt-4o-mini") # Override model only
        end
      end

      backend_def = swarm.agent_definition(:backend)
      frontend_def = swarm.agent_definition(:frontend)

      # Backend inherits all
      assert_equal("gpt-4o", backend_def.model)
      assert_equal(:openai, backend_def.provider)
      assert_equal("http://proxy.com/v1", backend_def.base_url)
      assert_equal(180, backend_def.timeout)
      assert_in_delta(0.7, backend_def.parameters[:temperature])
      assert_equal("value", backend_def.headers["X-Common"])
      refute(backend_def.coding_agent)

      # Frontend overrides model, inherits rest
      assert_equal("gpt-4o-mini", frontend_def.model) # Overridden
      assert_equal(:openai, frontend_def.provider) # Inherited
      assert_equal("http://proxy.com/v1", frontend_def.base_url) # Inherited
    end

    def test_agent_provider_overrides_all_agents
      swarm = SwarmSDK.build do
        name("Provider Override Test")
        lead(:agent1)

        all_agents do
          provider(:openai)
          base_url("http://openai-proxy.com/v1")
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4")
          # Inherits openai provider
        end

        agent(:agent2) do
          description("Agent 2")
          model("claude-3-5-sonnet-20241022")
          provider(:anthropic) # Override to anthropic
          # base_url should be inherited but makes no sense for anthropic
        end
      end

      agent1_def = swarm.agent_definition(:agent1)
      agent2_def = swarm.agent_definition(:agent2)

      assert_equal(:openai, agent1_def.provider) # Inherited
      assert_equal(:anthropic, agent2_def.provider) # Overridden
    end

    def test_all_agents_api_version_inherited
      swarm = SwarmSDK.build do
        name("API Version Test")
        lead(:agent1)

        all_agents do
          provider(:openai)
          api_version("v1/responses")
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4")
          # Should inherit api_version
        end

        agent(:agent2) do
          description("Agent 2")
          model("gpt-4")
          api_version("v1/chat/completions") # Override
        end
      end

      agent1_def = swarm.agent_definition(:agent1)
      agent2_def = swarm.agent_definition(:agent2)

      assert_equal("v1/responses", agent1_def.api_version) # Inherited
      assert_equal("v1/chat/completions", agent2_def.api_version) # Overridden
    end

    def test_all_agents_parameters_pure_inheritance
      # Test when agent has NO parameters - should inherit all_agents
      swarm = SwarmSDK.build do
        name("Parameters Pure Inheritance")
        lead(:agent1)

        all_agents do
          parameters({ temperature: 0.7, max_tokens: 1000, top_p: 0.9 })
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4")
          # No parameters - should inherit ALL from all_agents
        end
      end

      agent1_def = swarm.agent_definition(:agent1)

      # Should have all three parameters from all_agents
      assert_in_delta(0.7, agent1_def.parameters[:temperature])
      assert_equal(1000, agent1_def.parameters[:max_tokens])
      assert_in_delta(0.9, agent1_def.parameters[:top_p])
    end

    def test_all_agents_headers_pure_inheritance
      # Test when agent has NO headers - should inherit all_agents
      swarm = SwarmSDK.build do
        name("Headers Pure Inheritance")
        lead(:agent1)

        all_agents do
          headers({ "X-Header-1" => "value1", "X-Header-2" => "value2" })
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4")
          # No headers - should inherit ALL from all_agents
        end
      end

      agent1_def = swarm.agent_definition(:agent1)

      # Should have both headers from all_agents
      assert_equal("value1", agent1_def.headers["X-Header-1"])
      assert_equal("value2", agent1_def.headers["X-Header-2"])
    end

    def test_all_agents_parameters_empty_agent
      # Edge case: all_agents has parameters, agent explicitly sets empty hash
      swarm = SwarmSDK.build do
        name("Empty Agent Parameters")
        lead(:agent1)

        all_agents do
          parameters({ temperature: 0.7 })
        end

        agent(:agent1) do
          description("Agent 1")
          model("gpt-4")
          parameters({}) # Explicit empty - should still get all_agents merged
        end
      end

      agent1_def = swarm.agent_definition(:agent1)

      # Should still have all_agents parameters (empty hash merged with all_agents)
      assert_in_delta(0.7, agent1_def.parameters[:temperature])
    end
  end
end
