# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class EnableThinkToolTest < Minitest::Test
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

    def test_think_tool_enabled_by_default
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write],
      ))

      agent = swarm.agent(:developer)

      # Should have Think tool by default
      assert(agent.tools.key?(:Think), "Should have Think tool by default")
    end

    def test_think_tool_can_be_disabled_via_config
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write],
        enable_think_tool: false, # Disable Think tool
      ))

      agent = swarm.agent(:developer)

      # Should NOT have Think tool
      refute(agent.tools.key?(:Think), "Should NOT have Think tool when disabled")

      # Should still have other default tools
      assert(agent.tools.key?(:Read), "Should still have Read")
      assert(agent.tools.key?(:Grep), "Should still have Grep")
    end

    def test_think_tool_explicit_enable
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write],
        enable_think_tool: true, # Explicitly enable
      ))

      agent = swarm.agent(:developer)

      # Should have Think tool
      assert(agent.tools.key?(:Think), "Should have Think tool when explicitly enabled")
    end

    def test_think_tool_disabled_with_all_defaults_enabled
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [],
        include_default_tools: true, # Default tools enabled
        enable_think_tool: false, # But Think disabled
      ))

      agent = swarm.agent(:developer)

      # Should have other default tools
      assert(agent.tools.key?(:Read), "Should have Read")
      assert(agent.tools.key?(:Grep), "Should have Grep")
      assert(agent.tools.key?(:ScratchpadWrite), "Should have ScratchpadWrite")

      # Should NOT have Think tool
      refute(agent.tools.key?(:Think), "Should NOT have Think when explicitly disabled")
    end

    def test_think_tool_with_dsl
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:agent1)

        agent(:agent1) do
          description("Test agent")
          model("gpt-5")
          system_prompt("Test")
          enable_think_tool(false) # Disable via DSL
        end
      end

      agent_chat = swarm.agent(:agent1)

      # Should NOT have Think tool
      refute(agent_chat.tools.key?(:Think), "Should NOT have Think when disabled via DSL")

      # Should still have other default tools
      assert(agent_chat.tools.key?(:Read), "Should have Read")
    end

    def test_think_tool_enabled_via_dsl
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:agent1)

        agent(:agent1) do
          description("Test agent")
          model("gpt-5")
          system_prompt("Test")
          enable_think_tool(true) # Explicitly enable via DSL
        end
      end

      agent_chat = swarm.agent(:agent1)

      # Should have Think tool
      assert(agent_chat.tools.key?(:Think), "Should have Think when enabled via DSL")
    end

    def test_think_tool_disabled_when_default_tools_disabled
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write],
        include_default_tools: false, # Disable all default tools
        enable_think_tool: true, # This should be ignored
      ))

      agent = swarm.agent(:developer)

      # Should NOT have Think or any default tools
      refute(agent.tools.key?(:Think), "Should NOT have Think when default tools disabled")
      refute(agent.tools.key?(:Read), "Should NOT have Read")
      refute(agent.tools.key?(:Grep), "Should NOT have Grep")

      # Should only have explicit tool
      assert(agent.tools.key?(:Write), "Should have Write")
    end
  end
end
