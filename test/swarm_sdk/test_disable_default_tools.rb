# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class DisableDefaultToolsTest < Minitest::Test
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

    def test_default_tools_included_by_default
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write],
      ))

      agent = swarm.agent(:developer)

      # Should have all default tools
      assert(agent.tools.key?(:Think), "Should have Think")
      assert(agent.tools.key?(:Read), "Should have Read")
      assert(agent.tools.key?(:Grep), "Should have Grep")
    end

    def test_disable_all_default_tools
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write],
        disable_default_tools: true, # Disable ALL default tools
      ))

      agent = swarm.agent(:developer)

      # Should NOT have any default tools
      refute(agent.tools.key?(:Think), "Should NOT have Think")
      refute(agent.tools.key?(:Read), "Should NOT have Read")
      refute(agent.tools.key?(:Grep), "Should NOT have Grep")
      refute(agent.tools.key?(:TodoWrite), "Should NOT have TodoWrite")

      # Should only have explicit tool
      assert(agent.tools.key?(:Write), "Should have Write")
    end

    def test_disable_specific_default_tools
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write],
        disable_default_tools: [:Think, :TodoWrite], # Disable only these
      ))

      agent = swarm.agent(:developer)

      # Should NOT have disabled tools
      refute(agent.tools.key?(:Think), "Should NOT have Think")
      refute(agent.tools.key?(:TodoWrite), "Should NOT have TodoWrite")

      # Should have other default tools
      assert(agent.tools.key?(:Read), "Should have Read")
      assert(agent.tools.key?(:Grep), "Should have Grep")
      assert(agent.tools.key?(:Glob), "Should have Glob")
      assert(agent.tools.key?(:ScratchpadWrite), "Should have ScratchpadWrite")

      # Should have explicit tool
      assert(agent.tools.key?(:Write), "Should have Write")
    end

    def test_disable_default_tools_via_dsl_true
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:agent1)

        agent(:agent1) do
          description("Test agent")
          model("gpt-5")
          system_prompt("Test")
          tools(:Write)
          disable_default_tools(true) # Disable all
        end
      end

      agent_chat = swarm.agent(:agent1)

      # Should NOT have any default tools
      refute(agent_chat.tools.key?(:Think), "Should NOT have Think")
      refute(agent_chat.tools.key?(:Read), "Should NOT have Read")

      # Should have explicit tool
      assert(agent_chat.tools.key?(:Write), "Should have Write")
    end

    def test_disable_default_tools_via_dsl_array
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:agent1)

        agent(:agent1) do
          description("Test agent")
          model("gpt-5")
          system_prompt("Test")
          disable_default_tools([:Think, :Grep]) # Disable specific tools
        end
      end

      agent_chat = swarm.agent(:agent1)

      # Should NOT have disabled tools
      refute(agent_chat.tools.key?(:Think), "Should NOT have Think")
      refute(agent_chat.tools.key?(:Grep), "Should NOT have Grep")

      # Should have other default tools
      assert(agent_chat.tools.key?(:Read), "Should have Read")
      assert(agent_chat.tools.key?(:Glob), "Should have Glob")
    end

    def test_backward_compatibility_include_default_tools_false
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write],
        include_default_tools: false, # Legacy way to disable
      ))

      agent = swarm.agent(:developer)

      # Should NOT have any default tools
      refute(agent.tools.key?(:Think), "Should NOT have Think")
      refute(agent.tools.key?(:Read), "Should NOT have Read")

      # Should have explicit tool
      assert(agent.tools.key?(:Write), "Should have Write")
    end

    def test_disable_default_tools_takes_precedence_over_include
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write],
        include_default_tools: true, # Legacy: enable all
        disable_default_tools: [:Think], # New: disable Think
      ))

      agent = swarm.agent(:developer)

      # disable_default_tools should win
      refute(agent.tools.key?(:Think), "Should NOT have Think (disable wins)")
      assert(agent.tools.key?(:Read), "Should have Read")
    end
  end
end
