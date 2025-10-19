# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ValidationTest < Minitest::Test
    def test_definition_validate_returns_empty_for_valid_model
      definition = Agent::Definition.new(:test, {
        description: "Test agent",
        model: "gpt-4o-mini", # Known model in registry
        provider: "openai",
      })

      warnings = definition.validate

      assert_empty(warnings)
    end

    def test_definition_validate_returns_warning_for_invalid_model
      definition = Agent::Definition.new(:test, {
        description: "Test agent",
        model: "nonexistent-model-12345",
        provider: "openai",
      })

      warnings = definition.validate

      assert_equal(1, warnings.size)

      warning = warnings.first

      assert_equal(:model_not_found, warning[:type])
      assert_equal(:test, warning[:agent])
      assert_equal("nonexistent-model-12345", warning[:model])
      assert_includes(warning[:error_message], "nonexistent-model-12345")
      assert_instance_of(Array, warning[:suggestions])
    end

    def test_definition_validate_suggests_similar_models
      definition = Agent::Definition.new(:test, {
        description: "Test agent",
        model: "gpt-4-mini", # Close to gpt-4o-mini
        provider: "openai",
      })

      warnings = definition.validate
      warning = warnings.first

      # Should suggest similar gpt models with "mini" in the name
      suggestions = warning[:suggestions]

      # Suggestions should be an array (might be empty if no similar models found)
      assert_instance_of(Array, suggestions)

      # If suggestions exist, verify structure
      if suggestions.any?
        suggestion = suggestions.first

        assert(suggestion[:id])
        assert(suggestion.key?(:context_window))
        # Should have "gpt" or "mini" in suggestions
        assert(suggestions.any? { |s| s[:id].downcase.include?("gpt") || s[:id].downcase.include?("mini") })
      end
    end

    def test_definition_validate_warns_even_with_assume_model_exists
      definition = Agent::Definition.new(:test, {
        description: "Test agent",
        model: "custom-proxy-model",
        provider: "openai",
        assume_model_exists: true,
      })

      warnings = definition.validate

      assert_equal(1, warnings.size, "Should warn even when assume_model_exists is true (for user awareness)")
      assert_equal(:model_not_found, warnings.first[:type])
    end

    def test_definition_validate_warns_even_with_base_url
      definition = Agent::Definition.new(:test, {
        description: "Test agent",
        model: "custom-proxy-model",
        provider: "openai",
        base_url: "http://localhost:8000",
      })

      warnings = definition.validate

      assert_equal(1, warnings.size, "Should warn even when base_url is set (informs about context tracking)")
      assert_equal(:model_not_found, warnings.first[:type])
      assert_equal("custom-proxy-model", warnings.first[:model])
    end

    def test_swarm_validate_aggregates_warnings_from_all_agents
      swarm = Swarm.new(name: "Test Swarm", scratchpad: Tools::Stores::ScratchpadStorage.new)

      # Add agent with invalid model
      swarm.add_agent(Agent::Definition.new(:agent1, {
        description: "Agent 1",
        model: "invalid-model-1",
      }))

      # Add agent with valid model
      swarm.add_agent(Agent::Definition.new(:agent2, {
        description: "Agent 2",
        model: "gpt-4o-mini",
      }))

      # Add agent with invalid model
      swarm.add_agent(Agent::Definition.new(:agent3, {
        description: "Agent 3",
        model: "invalid-model-3",
      }))

      warnings = swarm.validate

      assert_equal(2, warnings.size, "Should have 2 warnings (agent1 and agent3)")
      assert_equal([:agent1, :agent3], warnings.map { |w| w[:agent] }.sort)
    end

    def test_swarm_validate_returns_empty_when_all_agents_valid
      swarm = Swarm.new(name: "Test Swarm", scratchpad: Tools::Stores::ScratchpadStorage.new)

      swarm.add_agent(Agent::Definition.new(:agent1, {
        description: "Agent 1",
        model: "gpt-4o-mini",
      }))

      swarm.add_agent(Agent::Definition.new(:agent2, {
        description: "Agent 2",
        model: "gpt-4o",
      }))

      warnings = swarm.validate

      assert_empty(warnings)
    end

    def test_swarm_validate_handles_proxy_configurations
      swarm = Swarm.new(name: "Test Swarm", scratchpad: Tools::Stores::ScratchpadStorage.new)

      # Proxy agent - should still warn (for user awareness about context tracking)
      swarm.add_agent(Agent::Definition.new(:proxy_agent, {
        description: "Proxy agent",
        model: "custom-proxy-model",
        provider: "openai",
        base_url: "http://proxy.local/v1",
      }))

      # Non-proxy agent with invalid model - should also warn
      swarm.add_agent(Agent::Definition.new(:direct_agent, {
        description: "Direct agent",
        model: "invalid-model",
      }))

      warnings = swarm.validate

      assert_equal(2, warnings.size, "Both agents should have warnings")
      assert_equal([:direct_agent, :proxy_agent], warnings.map { |w| w[:agent] }.sort)
    end

    def test_validation_warning_structure
      definition = Agent::Definition.new(:test, {
        description: "Test",
        model: "invalid-model",
      })

      warnings = definition.validate
      warning = warnings.first

      # Verify warning has all required fields
      assert_equal(:model_not_found, warning[:type])
      assert_equal(:test, warning[:agent])
      assert_equal("invalid-model", warning[:model])
      assert(warning[:error_message])
      assert_instance_of(Array, warning[:suggestions])
    end

    def test_suggest_similar_models_finds_partial_matches
      definition = Agent::Definition.new(:test, {
        description: "Test",
        model: "claudesonnet", # Missing hyphens
      })

      warnings = definition.validate
      suggestions = warnings.first[:suggestions]

      # Should suggest claude-sonnet models
      assert(suggestions.any? { |s| s[:id].include?("claude") && s[:id].include?("sonnet") })
    end

    def test_suggest_similar_models_normalizes_separators
      definition = Agent::Definition.new(:test, {
        description: "Test",
        model: "gpt_4o_mini", # Underscores instead of hyphens
      })

      warnings = definition.validate
      suggestions = warnings.first[:suggestions]

      # Should find gpt models with similar pattern (normalization works)
      assert_predicate(suggestions, :any?, "Should find similar models despite different separators")
      assert(suggestions.any? { |s| s[:id].downcase.include?("gpt") && s[:id].downcase.include?("mini") })
    end

    def test_suggest_similar_models_limits_to_three
      definition = Agent::Definition.new(:test, {
        description: "Test",
        model: "gpt", # Very generic query
      })

      warnings = definition.validate
      suggestions = warnings.first[:suggestions]

      assert_operator(suggestions.size, :<=, 3, "Should limit suggestions to 3")
    end

    def test_validate_handles_missing_rubyllm_gracefully
      # This tests the rescue block in suggest_similar_models
      definition = Agent::Definition.new(:test, {
        description: "Test",
        model: "test-model",
      })

      # Mock RubyLLM.models to raise an error
      RubyLLM.models.stub(:all, -> { raise StandardError, "Registry unavailable" }) do
        warnings = definition.validate

        # Should still return warning, just with empty suggestions
        assert_equal(1, warnings.size)
        assert_empty(warnings.first[:suggestions])
      end
    end
  end
end
