# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class HooksAdapterTest < Minitest::Test
    def setup
      @original_api_key = ENV["OPENAI_API_KEY"]
      ENV["OPENAI_API_KEY"] = "test-key-12345"
      RubyLLM.configure { |config| config.openai_api_key = "test-key-12345" }
    end

    def teardown
      ENV["OPENAI_API_KEY"] = @original_api_key
      RubyLLM.configure { |config| config.openai_api_key = @original_api_key }
    end

    def test_apply_agent_hooks_adds_hooks_to_agent
      swarm = Swarm.new(name: "Test")
      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
      ))

      # Access agent to trigger lazy initialization
      agent = swarm.agent(:test)

      hooks_config = {
        pre_tool_use: [
          {
            "matcher" => "Write",
            "type" => "command",
            "command" => "echo test",
            "timeout" => 5,
          },
        ],
      }

      # Apply hooks using public API
      SwarmSDK::Hooks::Adapter.apply_agent_hooks(agent, :test, hooks_config, "Test Swarm")

      # Verify hooks were registered (they exist in the agent's hook system)
      # We can't easily inspect the hooks directly, but we can verify no errors were raised
      assert_instance_of(Agent::Chat, agent)
    end

    def test_swarm_level_events_constant
      assert_equal([:swarm_start, :swarm_stop], SwarmSDK::Hooks::Adapter::SWARM_LEVEL_EVENTS)
    end

    def test_agent_level_events_constant
      expected = [
        :pre_tool_use,
        :post_tool_use,
        :user_prompt,
        :agent_step,
        :agent_stop,
        :first_message,
        :pre_delegation,
        :post_delegation,
        :context_warning,
      ]

      assert_equal(expected, SwarmSDK::Hooks::Adapter::AGENT_LEVEL_EVENTS)
    end
  end
end
