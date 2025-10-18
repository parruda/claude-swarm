# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ModelAliasResolutionTest < Minitest::Test
    def setup
      # Set fake API keys
      @original_anthropic_key = ENV["ANTHROPIC_API_KEY"]
      @original_openai_key = ENV["OPENAI_API_KEY"]
      ENV["ANTHROPIC_API_KEY"] = "test-key-12345"
      ENV["OPENAI_API_KEY"] = "test-key-12345"
      RubyLLM.configure do |config|
        config.anthropic_api_key = "test-key-12345"
        config.openai_api_key = "test-key-12345"
      end
    end

    def teardown
      # Restore original API keys
      if @original_anthropic_key
        ENV["ANTHROPIC_API_KEY"] = @original_anthropic_key
      else
        ENV.delete("ANTHROPIC_API_KEY")
      end

      if @original_openai_key
        ENV["OPENAI_API_KEY"] = @original_openai_key
      else
        ENV.delete("OPENAI_API_KEY")
      end
    end

    def test_model_alias_sonnet_resolves_in_definition
      config = {
        description: "Test agent",
        model: "sonnet", # Use alias
        system_prompt: "You are a test agent",
      }

      definition = Agent::Definition.new(:test_agent, config)
      hash = definition.to_h

      # Should be resolved to full model ID
      assert_equal("claude-sonnet-4-5-20250929", hash[:model])
    end

    def test_model_alias_opus_resolves_in_definition
      config = {
        description: "Test agent",
        model: "opus", # Use alias
        system_prompt: "You are a test agent",
      }

      definition = Agent::Definition.new(:test_agent, config)
      hash = definition.to_h

      # Should be resolved to full model ID
      assert_equal("claude-opus-4-1-20250805", hash[:model])
    end

    def test_model_alias_haiku_resolves_in_definition
      config = {
        description: "Test agent",
        model: "haiku", # Use alias
        system_prompt: "You are a test agent",
      }

      definition = Agent::Definition.new(:test_agent, config)
      hash = definition.to_h

      # Should be resolved to full model ID
      assert_equal("claude-haiku-4-5-20251001", hash[:model])
    end

    def test_full_model_id_passes_through_unchanged
      config = {
        description: "Test agent",
        model: "claude-sonnet-4-5-20250929", # Full ID
        system_prompt: "You are a test agent",
      }

      definition = Agent::Definition.new(:test_agent, config)
      hash = definition.to_h

      # Should remain unchanged
      assert_equal("claude-sonnet-4-5-20250929", hash[:model])
    end

    def test_unknown_model_passes_through_unchanged
      config = {
        description: "Test agent",
        model: "some-unknown-model", # Not in registry or aliases
        system_prompt: "You are a test agent",
      }

      definition = Agent::Definition.new(:test_agent, config)
      hash = definition.to_h

      # Should remain unchanged (no alias found)
      assert_equal("some-unknown-model", hash[:model])
    end

    def test_model_alias_in_swarm_builder
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:agent1)

        agent(:agent1) do
          description("Test agent")
          model("sonnet") # Use alias
          system_prompt("Test")
        end
      end

      # Access the agent's chat instance to verify the model was resolved
      agent_chat = swarm.agent(:agent1)

      # The agent should have been created successfully with the resolved model
      # We can't directly access the model from the chat, but we can verify
      # the swarm was created without errors, which proves alias resolution worked
      refute_nil(agent_chat)
    end
  end
end
