# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Hooks
    class TestFinishActions < Minitest::Test
      # Test finish_agent behavior - exits current agent, swarm continues if delegated
      def test_finish_agent_from_pre_tool_use_hook
        swarm = build_test_swarm_with_delegation

        # Add pre_tool_use hook that finishes the agent on Read tool
        swarm.agent_definition(:backend).add_hook(:pre_tool_use, matcher: "Read") do |ctx|
          ctx.finish_agent("Backend finished early!")
        end

        # Mock the OpenAI API response for the lead agent
        # Lead will delegate to backend, backend will finish immediately
        stub_openai_delegation_then_final

        # Execute swarm - should complete with the finish message
        result = swarm.execute("Test task")

        assert_predicate(result, :success?)
        assert_includes(result.content, "Task completed") # From final lead response
      end

      def test_finish_agent_from_post_tool_use_hook
        swarm = build_single_agent_swarm

        # Add post_tool_use hook that finishes the agent after Write tool
        swarm.agent_definition(:lead).add_hook(:post_tool_use, matcher: "Write") do |ctx|
          ctx.finish_agent("Work is done!")
        end

        # Mock the OpenAI API - lead will use Write tool, then finish
        stub_openai_tool_then_finish_agent

        result = swarm.execute("Write a file")

        assert_predicate(result, :success?)
        assert_equal("Work is done!", result.content)
      end

      def test_finish_agent_from_user_prompt_hook
        swarm = build_single_agent_swarm

        # Add user_prompt hook that finishes immediately
        swarm.agent_definition(:lead).add_hook(:user_prompt) do |ctx|
          ctx.finish_agent("Task rejected: #{ctx.metadata[:prompt]}")
        end

        # No OpenAI API call needed - hook intercepts before LLM call
        result = swarm.execute("Do something")

        assert_predicate(result, :success?)
        assert_equal("Task rejected: Do something", result.content)
      end

      # Test finish_swarm behavior - exits entire swarm immediately
      def test_finish_swarm_from_pre_tool_use_hook
        swarm = build_single_agent_swarm

        # Add pre_tool_use hook that finishes the swarm on any tool
        swarm.agent_definition(:lead).add_hook(:pre_tool_use) do |ctx|
          ctx.finish_swarm("Swarm finished early!")
        end

        # Mock the OpenAI API - lead will try to use a tool, swarm finishes
        stub_openai_tool_call_only

        result = swarm.execute("Test task")

        assert_predicate(result, :success?)
        assert_equal("Swarm finished early!", result.content)
      end

      def test_finish_swarm_from_post_tool_use_hook
        swarm = build_single_agent_swarm

        # Add post_tool_use hook that finishes the swarm after any tool
        swarm.agent_definition(:lead).add_hook(:post_tool_use) do |ctx|
          ctx.finish_swarm("Found the answer!")
        end

        # Mock the OpenAI API - lead will use a tool, then swarm finishes
        stub_openai_tool_then_finish_swarm

        result = swarm.execute("Find answer")

        assert_predicate(result, :success?)
        assert_equal("Found the answer!", result.content)
      end

      def test_finish_swarm_from_user_prompt_hook
        swarm = build_single_agent_swarm

        # Add user_prompt hook that finishes swarm immediately
        swarm.agent_definition(:lead).add_hook(:user_prompt) do |ctx|
          ctx.finish_swarm("Swarm stopped before execution")
        end

        # No OpenAI API call needed - hook intercepts before LLM call
        result = swarm.execute("Do something")

        assert_predicate(result, :success?)
        assert_equal("Swarm stopped before execution", result.content)
      end

      # Test finish_swarm propagates through delegation chain
      def test_finish_swarm_propagates_from_delegated_agent
        swarm = build_test_swarm_with_delegation

        # Add hook to backend that finishes the swarm
        swarm.agent_definition(:backend).add_hook(:pre_tool_use, matcher: "Read") do |ctx|
          ctx.finish_swarm("Backend found the answer!")
        end

        # Mock the OpenAI API - lead delegates to backend, backend finishes swarm
        stub_openai_delegation_then_swarm_finish

        result = swarm.execute("Test task")

        assert_predicate(result, :success?)
        assert_equal("Backend found the answer!", result.content)
      end

      # Test convenience methods work without SwarmSDK::Hooks::Result prefix
      def test_convenience_methods_available_on_context
        swarm = build_single_agent_swarm

        # Test all convenience methods are available on context object
        swarm.agent_definition(:lead).add_hook(:pre_tool_use) do |ctx|
          # All these should work via context object (no SwarmSDK::Hooks::Result prefix needed)
          case ctx.tool_call.name
          when "Halt"
            ctx.halt("Halted!")
          when "Replace"
            ctx.replace("Replaced!")
          when "Reprompt"
            ctx.reprompt("Reprompted!")
          when "FinishAgent"
            ctx.finish_agent("Agent finished!")
          when "FinishSwarm"
            ctx.finish_swarm("Swarm finished!")
          end
        end

        # Test halt
        stub_openai_halt_tool
        assert_raises(Hooks::Error) do
          swarm.execute("Use Halt tool")
        end

        # Test finish_swarm (most relevant)
        stub_openai_finish_swarm_tool
        result = swarm.execute("Use FinishSwarm tool")

        assert_equal("Swarm finished!", result.content)
      end

      # Test finish actions work in parallel tool calls
      def test_finish_agent_with_parallel_tools
        swarm = build_single_agent_swarm

        # Add hook that finishes on second tool
        call_count = 0
        swarm.agent_definition(:lead).add_hook(:post_tool_use) do |ctx|
          call_count += 1
          ctx.finish_agent("Finished after #{call_count} tools") if call_count == 2
        end

        # Mock the OpenAI API - lead will use 3 tools in parallel
        stub_openai_parallel_tools

        result = swarm.execute("Use multiple tools")

        # All 3 tools should execute (in parallel), then agent finishes
        assert_predicate(result, :success?)
        assert_equal("Finished after 2 tools", result.content)
      end

      def test_finish_swarm_with_parallel_tools
        swarm = build_single_agent_swarm

        # Add hook that finishes swarm on first tool completion
        swarm.agent_definition(:lead).add_hook(:post_tool_use, matcher: "Read") do |ctx|
          ctx.finish_swarm("Swarm finished!")
        end

        # Mock the OpenAI API - lead will use 3 tools in parallel
        stub_openai_parallel_tools_with_read

        result = swarm.execute("Use multiple tools")

        # All tools execute in parallel, then swarm finishes
        assert_predicate(result, :success?)
        assert_equal("Swarm finished!", result.content)
      end

      private

      def build_single_agent_swarm
        SwarmSDK.build do
          name("Test Swarm")
          lead(:lead)

          agent(:lead) do
            model("gpt-4")
            description("Lead agent")
            prompt("You are the lead")
            tools(:Read, :Write, :Bash)
          end
        end
      end

      def build_test_swarm_with_delegation
        SwarmSDK.build do
          name("Test Swarm")
          lead(:lead)

          agent(:lead) do
            model("gpt-4")
            description("Lead agent")
            prompt("You are the lead")
            delegates_to(:backend)
          end

          agent(:backend) do
            model("gpt-4")
            description("Backend agent")
            prompt("You handle backend tasks")
            tools(:Read, :Write)
          end
        end
      end

      # Stub helpers for OpenAI API responses

      def stub_openai_delegation_then_final
        # First call: Lead delegates to backend
        stub_openai_chat_completion(
          response: {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: nil,
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: {
                        name: "task__backend",
                        arguments: '{"task":"Do backend work"}',
                      },
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
          },
        )

        # Backend finishes immediately (hook will intercept)
        # No need to stub backend response since hook returns directly

        # Final lead response after backend finishes
        stub_openai_chat_completion(
          response: {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: "Task completed",
                },
                finish_reason: "stop",
              },
            ],
          },
        )
      end

      def stub_openai_tool_then_finish_agent
        # First call: Lead uses Write tool
        stub_openai_chat_completion(
          response: {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: nil,
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: {
                        name: "Write",
                        arguments: '{"file_path":"test.txt","content":"test"}',
                      },
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
          },
        )

        # Hook will finish agent after Write tool - no second LLM call
      end

      def stub_openai_tool_call_only
        # Lead tries to use a tool
        stub_openai_chat_completion(
          response: {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: nil,
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: {
                        name: "Read",
                        arguments: '{"file_path":"test.txt"}',
                      },
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
          },
        )

        # Hook will finish swarm before tool executes
      end

      def stub_openai_tool_then_finish_swarm
        # Lead uses a tool
        stub_openai_chat_completion(
          response: {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: nil,
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: {
                        name: "Read",
                        arguments: '{"file_path":"test.txt"}',
                      },
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
          },
        )

        # Hook will finish swarm after Read tool
      end

      def stub_openai_delegation_then_swarm_finish
        # Lead delegates to backend
        stub_openai_chat_completion(
          response: {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: nil,
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: {
                        name: "task__backend",
                        arguments: '{"task":"Do backend work"}',
                      },
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
          },
        )

        # Backend tries to use Read tool (hook will finish swarm)
        # No additional stubs needed - hook intercepts
      end

      def stub_openai_halt_tool
        stub_openai_chat_completion(
          response: {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: nil,
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: {
                        name: "Halt",
                        arguments: "{}",
                      },
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
          },
        )
      end

      def stub_openai_finish_swarm_tool
        stub_openai_chat_completion(
          response: {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: nil,
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: {
                        name: "FinishSwarm",
                        arguments: "{}",
                      },
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
          },
        )
      end

      def stub_openai_parallel_tools
        # Lead uses 3 tools in parallel
        stub_openai_chat_completion(
          response: {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: nil,
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: { name: "Write", arguments: '{"file_path":"1.txt","content":"1"}' },
                    },
                    {
                      id: "call_2",
                      type: "function",
                      function: { name: "Write", arguments: '{"file_path":"2.txt","content":"2"}' },
                    },
                    {
                      id: "call_3",
                      type: "function",
                      function: { name: "Write", arguments: '{"file_path":"3.txt","content":"3"}' },
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
          },
        )

        # Hook will finish agent after second tool
      end

      def stub_openai_parallel_tools_with_read
        # Lead uses 3 tools in parallel (including Read)
        stub_openai_chat_completion(
          response: {
            choices: [
              {
                message: {
                  role: "assistant",
                  content: nil,
                  tool_calls: [
                    {
                      id: "call_1",
                      type: "function",
                      function: { name: "Read", arguments: '{"file_path":"test.txt"}' },
                    },
                    {
                      id: "call_2",
                      type: "function",
                      function: { name: "Write", arguments: '{"file_path":"2.txt","content":"2"}' },
                    },
                    {
                      id: "call_3",
                      type: "function",
                      function: { name: "Bash", arguments: '{"command":"echo test"}' },
                    },
                  ],
                },
                finish_reason: "tool_calls",
              },
            ],
          },
        )

        # Hook will finish swarm when Read completes
      end

      def stub_openai_chat_completion(response:)
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(
            status: 200,
            body: response.to_json,
            headers: { "Content-Type" => "application/json" },
          )
      end
    end
  end
end
