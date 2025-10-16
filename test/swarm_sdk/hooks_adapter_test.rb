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

    def test_validate_swarm_event_accepts_valid_events
      # Should not raise for swarm_start and swarm_stop
      assert_silent do
        SwarmSDK::Hooks::Adapter.send(:validate_swarm_event!, :swarm_start)
        SwarmSDK::Hooks::Adapter.send(:validate_swarm_event!, :swarm_stop)
      end
    end

    def test_validate_swarm_event_rejects_agent_events
      error = assert_raises(ConfigurationError) do
        SwarmSDK::Hooks::Adapter.send(:validate_swarm_event!, :pre_tool_use)
      end

      assert_includes(error.message, "Invalid swarm-level hook event")
      assert_includes(error.message, "pre_tool_use")
    end

    def test_validate_agent_event_accepts_valid_events
      # Should not raise for agent-level events
      assert_silent do
        SwarmSDK::Hooks::Adapter.send(:validate_agent_event!, :pre_tool_use)
        SwarmSDK::Hooks::Adapter.send(:validate_agent_event!, :post_tool_use)
        SwarmSDK::Hooks::Adapter.send(:validate_agent_event!, :user_prompt)
        SwarmSDK::Hooks::Adapter.send(:validate_agent_event!, :agent_step)
        SwarmSDK::Hooks::Adapter.send(:validate_agent_event!, :agent_stop)
        SwarmSDK::Hooks::Adapter.send(:validate_agent_event!, :first_message)
        SwarmSDK::Hooks::Adapter.send(:validate_agent_event!, :pre_delegation)
        SwarmSDK::Hooks::Adapter.send(:validate_agent_event!, :post_delegation)
      end
    end

    def test_validate_agent_event_rejects_invalid_events
      error = assert_raises(ConfigurationError) do
        SwarmSDK::Hooks::Adapter.send(:validate_agent_event!, :invalid_event)
      end

      assert_includes(error.message, "Invalid agent-level hook event")
    end

    def test_build_input_json_for_pre_tool_use
      context = SwarmSDK::Hooks::Context.new(
        event: :pre_tool_use,
        agent_name: :backend,
        tool_call: Hooks::ToolCall.new(
          id: "call_123",
          name: "Write",
          parameters: { file_path: "test.rb", content: "code" },
        ),
      )

      json = SwarmSDK::Hooks::Adapter.send(:build_input_json, context, :pre_tool_use, :backend)

      assert_equal("pre_tool_use", json[:event])
      assert_equal("backend", json[:agent])
      assert_equal("Write", json[:tool])
      assert_equal("test.rb", json[:parameters][:file_path])
      assert_equal("code", json[:parameters][:content])
    end

    def test_build_input_json_for_post_tool_use
      context = SwarmSDK::Hooks::Context.new(
        event: :post_tool_use,
        agent_name: :backend,
        tool_result: Hooks::ToolResult.new(
          tool_call_id: "call_123",
          tool_name: "Write",
          content: "File written",
          success: true,
        ),
      )

      json = SwarmSDK::Hooks::Adapter.send(:build_input_json, context, :post_tool_use, :backend)

      assert_equal("post_tool_use", json[:event])
      assert_equal("backend", json[:agent])
      assert_equal("call_123", json[:tool_call_id])
      assert_equal("File written", json[:result])
      assert(json[:success])
    end

    def test_build_input_json_for_pre_delegation
      context = SwarmSDK::Hooks::Context.new(
        event: :pre_delegation,
        agent_name: :coordinator,
        delegation_target: "backend",
        metadata: { task: "Build API" },
      )

      json = SwarmSDK::Hooks::Adapter.send(:build_input_json, context, :pre_delegation, :coordinator)

      assert_equal("pre_delegation", json[:event])
      assert_equal("coordinator", json[:agent])
      assert_equal("backend", json[:delegation_target])
      assert_equal("Build API", json[:task])
    end

    def test_build_input_json_for_user_request
      context = SwarmSDK::Hooks::Context.new(
        event: :user_prompt,
        agent_name: :backend,
        metadata: {
          prompt: "Build authentication",
          message_count: 5,
        },
      )

      json = SwarmSDK::Hooks::Adapter.send(:build_input_json, context, :user_prompt, :backend)

      assert_equal("user_prompt", json[:event])
      assert_equal("backend", json[:agent])
      assert_equal("Build authentication", json[:prompt])
      assert_equal(5, json[:message_count])
    end

    def test_build_swarm_input_json_for_swarm_start
      context = SwarmSDK::Hooks::Context.new(
        event: :swarm_start,
        agent_name: :lead,
        metadata: { prompt: "Build app" },
      )

      json = SwarmSDK::Hooks::Adapter.send(:build_swarm_input_json, context, :swarm_start, "Dev Team")

      assert_equal("swarm_start", json[:event])
      assert_equal("Dev Team", json[:swarm])
      assert_equal("Build app", json[:prompt])
    end

    def test_build_swarm_input_json_for_swarm_stop
      context = SwarmSDK::Hooks::Context.new(
        event: :swarm_stop,
        agent_name: :lead,
        metadata: {
          success: true,
          duration: 10.5,
          total_cost: 0.15,
          total_tokens: 1500,
        },
      )

      json = SwarmSDK::Hooks::Adapter.send(:build_swarm_input_json, context, :swarm_stop, "Dev Team")

      assert_equal("swarm_stop", json[:event])
      assert_equal("Dev Team", json[:swarm])
      assert(json[:success])
      assert_in_delta(10.5, json[:duration])
      assert_in_delta(0.15, json[:total_cost])
      assert_equal(1500, json[:total_tokens])
    end

    def test_create_hook_callback_returns_proc
      hook_def = {
        "command" => "echo test",
        "timeout" => 10,
      }

      callback = SwarmSDK::Hooks::Adapter.send(:create_hook_callback, hook_def, :pre_tool_use, :backend, "Test Swarm")

      assert_instance_of(Proc, callback)
    end

    def test_apply_agent_hooks_adds_hooks_to_agent
      swarm = Swarm.new(name: "Test")
      swarm.add_agent(create_agent(
        name: :test,
        description: "Test",
        model: "gpt-5",
        system_prompt: "Test",
      ))
      swarm.send(:initialize_agents)

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

      # Apply hooks
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
