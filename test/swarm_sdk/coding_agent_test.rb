# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class CodingAgentTest < Minitest::Test
    def setup
      ENV["OPENAI_API_KEY"] = "test-key"
      RubyLLM.configure { |c| c.openai_api_key = "test-key" }
    end

    def test_default_behavior_includes_todo_scratchpad_info
      # Create AgentDefinition directly to test prompt building
      agent_def = Agent::Definition.new(
        :test_agent,
        description: "Test agent",
        model: "gpt-4",
        system_prompt: "Custom prompt",
      )

      # Default: coding_agent=false, default tools enabled
      refute(agent_def.coding_agent)
      assert_nil(agent_def.disable_default_tools)

      # Should include environment info + custom prompt
      # TodoWrite/Scratchpad instructions are now in tool descriptions, not system prompt
      assert_includes(agent_def.system_prompt, "Custom prompt")
      assert_includes(agent_def.system_prompt, "Today's date")
      refute_includes(agent_def.system_prompt, "TodoWrite")
      refute_includes(agent_def.system_prompt, "Scratchpad")
      # Should NOT include full coding base prompt
      refute_includes(agent_def.system_prompt, "You are an AI agent designed to help users")
    end

    def test_coding_agent_false_without_default_tools
      # coding_agent=false, disable_default_tools: true
      agent_def = Agent::Definition.new(
        :test_agent,
        description: "Test agent",
        model: "gpt-4",
        system_prompt: "Custom prompt",
        disable_default_tools: true,
      )

      refute(agent_def.coding_agent)
      assert(agent_def.disable_default_tools)

      # Should be ONLY the custom prompt (no TODO/Scratchpad info)
      assert_equal("Custom prompt", agent_def.system_prompt)
    end

    def test_coding_agent_includes_base_prompt
      custom_prompt = "This is my custom prompt for a coding agent."

      # Create AgentDefinition directly to test prompt building
      agent_def = Agent::Definition.new(
        :test_agent,
        description: "Test agent",
        model: "gpt-4",
        system_prompt: custom_prompt,
        coding_agent: true,
      )

      # coding_agent should be true
      assert(agent_def.coding_agent)

      # System prompt should include BOTH base prompt AND custom prompt
      refute_empty(agent_def.system_prompt)
      assert_operator(agent_def.system_prompt.length, :>, custom_prompt.length)
      assert_includes(agent_def.system_prompt, custom_prompt)
      # Should contain base prompt indicators like "working directory", "platform", etc.
      assert_match(/working directory|platform/i, agent_def.system_prompt)
    end

    def test_coding_agent_true_with_nil_custom_prompt
      # Create AgentDefinition directly to test prompt building
      agent_def = Agent::Definition.new(
        :test_agent,
        description: "Test agent",
        model: "gpt-4",
        system_prompt: nil,
        coding_agent: true,
      )

      # With coding_agent=true and nil custom_prompt, should get base prompt only
      refute_empty(agent_def.system_prompt)
      assert_match(/working directory|platform/i, agent_def.system_prompt)
    end

    def test_coding_agent_false_with_nil_custom_prompt
      # Create AgentDefinition directly to test prompt building
      agent_def = Agent::Definition.new(
        :test_agent,
        description: "Test agent",
        model: "gpt-4",
        system_prompt: nil,
        coding_agent: false,
      )

      # With coding_agent=false, default tools enabled, and nil custom_prompt
      # Should get environment info only (TodoWrite/Scratchpad info is in tool descriptions)
      refute_empty(agent_def.system_prompt)
      assert_includes(agent_def.system_prompt, "Today's date")
      assert_includes(agent_def.system_prompt, "Current Environment")
      refute_includes(agent_def.system_prompt, "TodoWrite")
      refute_includes(agent_def.system_prompt, "Scratchpad")
    end

    def test_coding_agent_false_with_nil_custom_prompt_no_default_tools
      # Create AgentDefinition directly to test prompt building
      agent_def = Agent::Definition.new(
        :test_agent,
        description: "Test agent",
        model: "gpt-4",
        system_prompt: nil,
        coding_agent: false,
        disable_default_tools: true,
      )

      # With coding_agent=false, disable_default_tools: true, and nil custom_prompt
      # Should get empty string
      assert_equal("", agent_def.system_prompt)
    end

    def test_coding_agent_false_ruby_dsl
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:custom_agent)

        agent(:custom_agent) do
          model("gpt-4")
          description("Custom agent")
          system_prompt("My custom prompt only")
          coding_agent(false) # Explicit false (same as default)
          tools(:Read, include_default: false) # Exclude default tools
        end
      end

      agent_def = swarm.agent_definition(:custom_agent)

      refute(agent_def.coding_agent)
      assert(agent_def.disable_default_tools)
      # Without default tools, should be exactly custom prompt
      assert_equal("My custom prompt only", agent_def.system_prompt)
    end

    def test_coding_agent_true_ruby_dsl
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:coding_agent)

        agent(:coding_agent) do
          model("gpt-4")
          description("Coding agent")
          system_prompt("Additional coding instructions")
          coding_agent(true) # Include base prompt
          tools(:Read)
        end
      end

      agent_def = swarm.agent_definition(:coding_agent)

      assert(agent_def.coding_agent)
      # Should have base + custom
      assert_operator(agent_def.system_prompt.length, :>, "Additional coding instructions".length)
      assert_includes(agent_def.system_prompt, "Additional coding instructions")
    end

    def test_coding_agent_false_yaml_configuration
      yaml_content = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: custom_agent
          agents:
            custom_agent:
              description: "Custom agent"
              model: gpt-4
              coding_agent: false
              disable_default_tools: true
              system_prompt: "Custom only"
              tools: [Read]
      YAML

      # Write temporary YAML file
      require "tempfile"
      file = Tempfile.new(["test_config", ".yml"])
      file.write(yaml_content)
      file.close

      begin
        config = Configuration.load_file(file.path)
        swarm = config.to_swarm

        agent_def = swarm.agent_definition(:custom_agent)

        refute(agent_def.coding_agent)
        assert(agent_def.disable_default_tools)
        # Without default tools, should be exactly custom prompt
        assert_equal("Custom only", agent_def.system_prompt)
      ensure
        file.unlink
      end
    end

    def test_coding_agent_true_yaml_configuration
      yaml_content = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: coding_agent
          agents:
            coding_agent:
              description: "Coding agent"
              model: gpt-4
              coding_agent: true
              system_prompt: "Additional instructions"
              tools: [Read]
      YAML

      # Write temporary YAML file
      require "tempfile"
      file = Tempfile.new(["test_config", ".yml"])
      file.write(yaml_content)
      file.close

      begin
        config = Configuration.load_file(file.path)
        swarm = config.to_swarm

        agent_def = swarm.agent_definition(:coding_agent)

        assert(agent_def.coding_agent)
        # Should have base + custom
        assert_operator(agent_def.system_prompt.length, :>, "Additional instructions".length)
        assert_includes(agent_def.system_prompt, "Additional instructions")
      ensure
        file.unlink
      end
    end

    def test_agent_definition_preserves_coding_agent_false
      agent_def = Agent::Definition.new(
        :test,
        description: "Test",
        model: "gpt-4",
        system_prompt: "Custom",
        coding_agent: false,
        disable_default_tools: true,
      )

      refute(agent_def.coding_agent)
      assert(agent_def.disable_default_tools)
      # Without default tools, exactly custom prompt
      assert_equal("Custom", agent_def.system_prompt)

      # Convert to hash and verify
      hash = agent_def.to_h

      refute(hash[:coding_agent])
    end

    def test_agent_definition_preserves_coding_agent_true
      agent_def = Agent::Definition.new(
        :test,
        description: "Test",
        model: "gpt-4",
        system_prompt: "Custom",
        coding_agent: true,
      )

      assert(agent_def.coding_agent)
      # Should have base + custom
      assert_operator(agent_def.system_prompt.length, :>, "Custom".length)

      # Convert to hash and verify
      hash = agent_def.to_h

      assert(hash[:coding_agent])
    end

    def test_multiple_agents_with_different_coding_agent_settings
      # Create AgentDefinitions directly to test prompt building
      non_coding_def = Agent::Definition.new(
        :non_coding_agent,
        description: "Non-coding agent",
        model: "gpt-4",
        system_prompt: "Custom prompt only",
        coding_agent: false,
        disable_default_tools: true, # No default tools
      )

      coding_def = Agent::Definition.new(
        :coding_agent,
        description: "Coding agent",
        model: "gpt-4",
        system_prompt: "Additional coding instructions",
        coding_agent: true,
      )

      # Non-coding agent has only custom prompt (no default tools)
      refute(non_coding_def.coding_agent)
      assert(non_coding_def.disable_default_tools)
      assert_equal("Custom prompt only", non_coding_def.system_prompt)

      # Coding agent has base + custom
      assert(coding_def.coding_agent)
      assert_operator(coding_def.system_prompt.length, :>, "Additional coding instructions".length)
      assert_includes(coding_def.system_prompt, "Additional coding instructions")
    end
  end
end
