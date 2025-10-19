# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class MemoryIntegrationTest < Minitest::Test
    def setup
      # Set fake API key to avoid RubyLLM configuration errors
      @original_api_key = ENV["ANTHROPIC_API_KEY"]
      ENV["ANTHROPIC_API_KEY"] = "test-key-12345"
      RubyLLM.configure do |config|
        config.anthropic_api_key = "test-key-12345"
      end

      @swarm = Swarm.new(name: "Test Swarm", scratchpad: Tools::Stores::MemoryStorage.new(persist_to: Dir.mktmpdir + "/memory-test.json"))

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

    def test_scratchpad_tools_work_across_agents
      # Test behavior: Verify scratchpad actually works by using the tools
      # This tests that scratchpad exists and is shared without checking internal state
      writer = @swarm.agent(:Writer)
      reader = @swarm.agent(:Reader)

      # Writer writes to scratchpad
      write_tool = writer.tools[:ScratchpadWrite]
      write_tool.execute(file_path: "test/data", content: "test_value", title: "Test Entry")

      # Reader can read from same scratchpad
      read_tool = reader.tools[:ScratchpadRead]
      result = read_tool.execute(file_path: "test/data")

      assert_includes(result, "test_value", "Reader should access Writer's scratchpad data")
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
      assert(writer.tools.key?(:ScratchpadList), "Writer should have scratchpad_list")

      # Reader has Read tool configured, but should also have scratchpad tools
      # Read tool has custom naming, so it's just :Read
      assert(reader.tools.key?(:Read), "Reader should have read tool")
      assert(reader.tools.key?(:ScratchpadWrite), "Reader should have scratchpad_write")
      assert(reader.tools.key?(:ScratchpadRead), "Reader should have scratchpad_read")
      assert(reader.tools.key?(:ScratchpadList), "Reader should have scratchpad_list")
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
      # Test behavior: Verify each swarm has isolated scratchpad storage
      swarm1 = Swarm.new(name: "Swarm 1")
      swarm2 = Swarm.new(name: "Swarm 2")

      # Add agents to both swarms
      swarm1.add_agent(create_agent(
        name: :Agent1,
        description: "Agent 1",
        model: "claude-sonnet-4",
        provider: "anthropic",
        system_prompt: "Agent 1",
      ))

      swarm2.add_agent(create_agent(
        name: :Agent2,
        description: "Agent 2",
        model: "claude-sonnet-4",
        provider: "anthropic",
        system_prompt: "Agent 2",
      ))

      # Write to swarm1's scratchpad
      agent1 = swarm1.agent(:Agent1)
      write_tool1 = agent1.tools[:ScratchpadWrite]
      write_tool1.execute(file_path: "test/shared", content: "swarm1_value", title: "Swarm 1 Data")

      # Write to swarm2's scratchpad with same path
      agent2 = swarm2.agent(:Agent2)
      write_tool2 = agent2.tools[:ScratchpadWrite]
      write_tool2.execute(file_path: "test/shared", content: "swarm2_value", title: "Swarm 2 Data")

      # Read from both - should have different values (isolated scratchpads)
      read_tool1 = agent1.tools[:ScratchpadRead]
      read_tool2 = agent2.tools[:ScratchpadRead]

      result1 = read_tool1.execute(file_path: "test/shared")
      result2 = read_tool2.execute(file_path: "test/shared")

      assert_includes(result1, "swarm1_value", "Swarm1 should have its own value")
      assert_includes(result2, "swarm2_value", "Swarm2 should have its own value")
    end
  end
end
