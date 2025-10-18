# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class DefaultToolsTest < Minitest::Test
    def setup
      # Set fake API keys to avoid RubyLLM configuration errors
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

    def test_default_tools_constant
      expected_tools = [
        :Read,
        :Grep,
        :Glob,
        :TodoWrite,
        :ScratchpadWrite,
        :ScratchpadRead,
        :ScratchpadList,
        :Think,
      ]

      assert_equal(expected_tools, Swarm::DEFAULT_TOOLS)
    end

    def test_agent_includes_default_tools_by_default
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write], # Explicitly configured tool
      ))

      agent = swarm.agent(:developer)

      # Should have explicitly configured tools
      assert(agent.tools.key?(:Write), "Should have Write")

      # Should have all default tools
      assert(agent.tools.key?(:Read), "Should have default Read")
      assert(agent.tools.key?(:Grep), "Should have default Grep")
      assert(agent.tools.key?(:Glob), "Should have default Glob")
      assert(agent.tools.key?(:TodoWrite), "Should have default TodoWrite")
      assert(agent.tools.key?(:ScratchpadWrite), "Should have default ScratchpadWrite")
      assert(agent.tools.key?(:ScratchpadRead), "Should have default ScratchpadRead")
      assert(agent.tools.key?(:ScratchpadList), "Should have default ScratchpadList")
      assert(agent.tools.key?(:Think), "Should have default Think")
    end

    def test_agent_can_exclude_default_tools
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [:Write, :Edit],
        disable_default_tools: true, # Disable defaults
      ))

      agent = swarm.agent(:developer)

      # Should have only explicitly configured tools
      assert(agent.tools.key?(:Write), "Should have Write")
      assert(agent.tools.key?(:Edit), "Should have Edit")

      # Should NOT have any default tools
      refute(agent.tools.key?(:Read), "Should NOT have Read")
      refute(agent.tools.key?(:Grep), "Should NOT have Grep")
      refute(agent.tools.key?(:ScratchpadWrite), "Should NOT have ScratchpadWrite")
    end

    def test_agent_with_no_tools_still_gets_defaults
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [], # No explicit tools
      ))

      agent = swarm.agent(:developer)

      # Should have all default tools
      assert(agent.tools.key?(:Read), "Should have default Read")
      assert(agent.tools.key?(:Grep), "Should have default Grep")
      assert(agent.tools.key?(:ScratchpadWrite), "Should have default ScratchpadWrite")
    end

    def test_agent_with_no_tools_and_no_defaults_has_nothing
      swarm = Swarm.new(name: "Test Swarm")

      swarm.add_agent(create_agent(
        name: :developer,
        description: "Developer agent",
        model: "gpt-5",
        system_prompt: "You are a developer.",
        tools: [],
        disable_default_tools: true,
      ))

      agent = swarm.agent(:developer)

      # Should have NO tools
      assert_empty(agent.tools, "Should have no tools")
    end
  end
end
