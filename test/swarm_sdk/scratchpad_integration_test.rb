# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ScratchpadIntegrationTest < Minitest::Test
    def setup
      # Set fake API key to avoid RubyLLM configuration errors
      @original_api_key = ENV["ANTHROPIC_API_KEY"]
      ENV["ANTHROPIC_API_KEY"] = "test-key-12345"
      RubyLLM.configure do |config|
        config.anthropic_api_key = "test-key-12345"
      end

      @swarm = Swarm.new(name: "Test Swarm")

      # Add agents WITHOUT explicitly requesting scratchpad tools
      # They should still get them because they're default tools
      @swarm.add_agent(create_agent(
        name: :Writer,
        description: "Writer agent",
        model: "claude-sonnet-4",
        provider: "anthropic",
        system_prompt: "You are a writer.",
        tools: [], # No tools explicitly configured
      ))

      @swarm.add_agent(create_agent(
        name: :Reader,
        description: "Reader agent",
        model: "claude-sonnet-4",
        provider: "anthropic",
        system_prompt: "You are a reader.",
        tools: [:Read], # Different tool, but should still get scratchpad
      ))
    end

    def teardown
      # Restore original API key
      ENV["ANTHROPIC_API_KEY"] = @original_api_key
      RubyLLM.configure do |config|
        config.anthropic_api_key = @original_api_key
      end
    end

    def test_scratchpad_instance_exists
      # Verify that the swarm has a scratchpad instance
      scratchpad = @swarm.instance_variable_get(:@scratchpad)

      refute_nil(scratchpad, "Swarm should have a scratchpad instance")
      assert_instance_of(Tools::Stores::Scratchpad, scratchpad)
    end

    def test_scratchpad_tools_are_always_available
      # Verify that scratchpad tools are automatically added even when not explicitly configured
      writer = @swarm.agent(:Writer)
      reader = @swarm.agent(:Reader)

      # Writer has no explicit tools, but should have scratchpad tools
      # Scratchpad tools use simple names without module namespacing
      assert(writer.tools.key?(:ScratchpadWrite), "Writer should have scratchpad_write")
      assert(writer.tools.key?(:ScratchpadRead), "Writer should have scratchpad_read")
      assert(writer.tools.key?(:ScratchpadList), "Writer should have scratchpad_list")

      # Reader has Read tool configured, but should also have scratchpad tools
      # Read tool has custom naming, so it's just :Read
      assert(reader.tools.key?(:Read), "Reader should have read tool")
      assert(reader.tools.key?(:ScratchpadWrite), "Reader should have scratchpad_write")
      assert(reader.tools.key?(:ScratchpadRead), "Reader should have scratchpad_read")
      assert(reader.tools.key?(:ScratchpadList), "Reader should have scratchpad_list")
    end

    def test_default_tools_are_always_available
      # Verify that all default tools (scratchpad, Read, Grep, Glob, TodoWrite) are automatically added
      writer = @swarm.agent(:Writer)
      reader = @swarm.agent(:Reader)

      # Both agents should have all default tools
      [writer, reader].each do |agent|
        # Scratchpad tools
        assert(agent.tools.key?(:ScratchpadWrite), "#{agent} should have scratchpad_write")
        assert(agent.tools.key?(:ScratchpadRead), "#{agent} should have scratchpad_read")
        assert(agent.tools.key?(:ScratchpadList), "#{agent} should have scratchpad_list")

        # File system tools
        assert(agent.tools.key?(:Read), "#{agent} should have read")
        assert(agent.tools.key?(:Grep), "#{agent} should have grep")
        assert(agent.tools.key?(:Glob), "#{agent} should have glob")

        # Task management
        assert(agent.tools.key?(:TodoWrite), "#{agent} should have todo_write")
      end
    end

    def test_each_swarm_has_separate_scratchpad
      # Each swarm instance gets its own scratchpad
      swarm1 = Swarm.new(name: "Swarm 1")
      swarm2 = Swarm.new(name: "Swarm 2")

      scratchpad1 = swarm1.instance_variable_get(:@scratchpad)
      scratchpad2 = swarm2.instance_variable_get(:@scratchpad)

      refute_nil(scratchpad1)
      refute_nil(scratchpad2)
      refute_same(scratchpad1, scratchpad2, "Each swarm should have its own scratchpad")
    end
  end
end
