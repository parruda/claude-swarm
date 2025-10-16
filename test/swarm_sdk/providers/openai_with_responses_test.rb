# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Providers
    class OpenAIWithResponsesTest < Minitest::Test
      def setup
        @config = RubyLLM::Configuration.new
        @config.openai_api_key = "test-key"
        @config.openai_api_base = "https://test.api"
      end

      def test_initialization_without_explicit_use_responses_api
        provider = OpenAIWithResponses.new(@config)

        assert_nil(provider.use_responses_api)
      end

      def test_initialization_with_explicit_use_responses_api_true
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        assert(provider.use_responses_api)
      end

      def test_initialization_with_explicit_use_responses_api_false
        provider = OpenAIWithResponses.new(@config, use_responses_api: false)

        refute(provider.use_responses_api)
      end

      def test_completion_url_returns_responses_when_explicit_true
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        assert_equal("responses", provider.completion_url)
      end

      def test_completion_url_returns_chat_completions_when_explicit_false
        provider = OpenAIWithResponses.new(@config, use_responses_api: false)

        assert_equal("chat/completions", provider.completion_url)
      end

      def test_completion_url_uses_chat_completions_by_default
        provider = OpenAIWithResponses.new(@config)

        # Without explicit configuration, defaults to chat/completions
        provider.instance_variable_set(:@model_id, "claude-sonnet-4-5-20250929")

        assert_equal("chat/completions", provider.completion_url)
      end

      def test_completion_url_with_explicit_responses_api_true
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        provider.instance_variable_set(:@model_id, "gemini-2.0-flash")

        assert_equal("responses", provider.completion_url)
      end

      def test_completion_url_auto_detects_gpt_models
        provider = OpenAIWithResponses.new(@config)

        provider.instance_variable_set(:@model_id, "gpt-5-mini")

        assert_equal("chat/completions", provider.completion_url)
      end

      def test_stream_url_matches_completion_url
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        assert_equal(provider.completion_url, provider.stream_url)
      end

      def test_requires_responses_api_returns_false_by_default
        provider = OpenAIWithResponses.new(@config)

        provider.instance_variable_set(:@model_id, "claude-3-5-sonnet-20241022")

        # No auto-detection - always returns false unless explicitly configured
        refute(provider.send(:requires_responses_api?))
      end

      def test_requires_responses_api_respects_explicit_configuration
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        provider.instance_variable_set(:@model_id, "gemini-1.5-pro")

        # When explicitly configured, should_use_responses_api returns true
        assert(provider.send(:should_use_responses_api?))
      end

      def test_requires_responses_api_returns_false_for_gpt_models
        provider = OpenAIWithResponses.new(@config)

        provider.instance_variable_set(:@model_id, "gpt-4o")

        refute(provider.send(:requires_responses_api?))
      end

      def test_requires_responses_api_returns_false_when_no_model_id
        provider = OpenAIWithResponses.new(@config)

        refute(provider.send(:requires_responses_api?))
      end

      def test_should_retry_with_responses_api_returns_true_for_relevant_errors
        provider = OpenAIWithResponses.new(@config)

        # Create a mock response object
        response = Struct.new(:body).new("This model is only supported in v1/responses and not in v1/chat/completions")
        error = RubyLLM::Error.new(response)

        assert(provider.send(:should_retry_with_responses_api?, error))
      end

      def test_should_retry_with_responses_api_returns_false_when_already_using_responses_api
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        response = Struct.new(:body).new("This model is only supported in v1/responses")
        error = RubyLLM::Error.new(response)

        refute(provider.send(:should_retry_with_responses_api?, error))
      end

      def test_should_retry_with_responses_api_returns_false_for_irrelevant_errors
        provider = OpenAIWithResponses.new(@config)

        response = Struct.new(:body).new("Some other error")
        error = RubyLLM::Error.new(response)

        refute(provider.send(:should_retry_with_responses_api?, error))
      end

      def test_response_id_ttl_prevents_expired_ids
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        # Simulate capturing a response ID
        provider.instance_variable_set(:@last_response_id, "resp_123")
        provider.instance_variable_set(:@last_response_time, Time.now - 400) # 400 seconds ago (expired)

        # Create mock messages with tool results
        messages = [
          RubyLLM::Message.new(role: :user, content: "Hello"),
          RubyLLM::Message.new(role: :assistant, content: "Hi"),
          RubyLLM::Message.new(role: :tool, content: "Result", tool_call_id: "call_1"),
        ]

        # Render payload - should NOT use expired response ID
        model = RubyLLM::Models.find("gpt-5")
        payload = provider.send(:render_responses_payload, messages, tools: {}, temperature: nil, model: model)

        # Should NOT have previous_response_id because it expired
        refute(payload.key?(:previous_response_id), "Should not use expired response ID")
        # Should have full input array (not just new messages)
        assert_kind_of(Array, payload[:input], "Should have input array")
      end

      def test_response_id_ttl_allows_fresh_ids
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        # Simulate capturing a recent response ID
        provider.instance_variable_set(:@last_response_id, "resp_123")
        provider.instance_variable_set(:@last_response_time, Time.now - 60) # 60 seconds ago (fresh)

        # Create mock messages with tool results
        messages = [
          RubyLLM::Message.new(role: :user, content: "Hello"),
          RubyLLM::Message.new(role: :assistant, content: "Hi"),
          RubyLLM::Message.new(role: :tool, content: "Result", tool_call_id: "call_1"),
        ]

        # Render payload - SHOULD use fresh response ID
        model = RubyLLM::Models.find("gpt-5")
        payload = provider.send(:render_responses_payload, messages, tools: {}, temperature: nil, model: model)

        # Should have previous_response_id because it's fresh
        assert_equal("resp_123", payload[:previous_response_id], "Should use fresh response ID")
      end

      def test_response_id_captured_with_timestamp
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        # Create mock response with ID
        response_body = {
          "id" => "resp_abc123",
          "output" => [
            { "type" => "message", "content" => [{ "type" => "output_text", "text" => "Hello" }] },
          ],
        }

        mock_response = Struct.new(:body).new(response_body)

        # Capture time before parsing
        before_time = Time.now

        # Parse response
        provider.send(:parse_responses_api_response, mock_response)

        # Verify response ID and timestamp were captured
        assert_equal("resp_abc123", provider.instance_variable_get(:@last_response_id))

        response_time = provider.instance_variable_get(:@last_response_time)

        assert(response_time, "Should have captured timestamp")
        assert_operator(response_time, :>=, before_time, "Timestamp should be recent")
        assert_operator(response_time, :<=, Time.now, "Timestamp should not be in future")
      end

      def test_has_new_messages_with_empty_array
        provider = OpenAIWithResponses.new(@config)

        refute(provider.send(:has_new_messages?, []))
      end

      def test_has_new_messages_with_tool_results
        provider = OpenAIWithResponses.new(@config)

        messages = [
          RubyLLM::Message.new(role: :user, content: "Hello"),
          RubyLLM::Message.new(role: :assistant, content: "Hi"),
          RubyLLM::Message.new(role: :tool, content: "Result", tool_call_id: "call_1"),
        ]

        assert(provider.send(:has_new_messages?, messages))
      end

      def test_has_new_messages_without_tool_results
        provider = OpenAIWithResponses.new(@config)

        messages = [
          RubyLLM::Message.new(role: :user, content: "Hello"),
          RubyLLM::Message.new(role: :assistant, content: "Hi"),
        ]

        refute(provider.send(:has_new_messages?, messages))
      end

      def test_format_new_input_messages_with_tool_results
        provider = OpenAIWithResponses.new(@config)

        messages = [
          RubyLLM::Message.new(role: :user, content: "Hello"),
          RubyLLM::Message.new(role: :assistant, content: "Hi"),
          RubyLLM::Message.new(role: :tool, content: "Tool result", tool_call_id: "call_123"),
        ]

        input = provider.send(:format_new_input_messages, messages)

        assert_equal(1, input.size)
        assert_equal("function_call_output", input[0][:type])
        assert_equal("call_123", input[0][:call_id])
        assert_equal("Tool result", input[0][:output])
      end

      def test_format_new_input_messages_with_user_messages
        provider = OpenAIWithResponses.new(@config)

        messages = [
          RubyLLM::Message.new(role: :user, content: "First"),
          RubyLLM::Message.new(role: :assistant, content: "Response"),
          RubyLLM::Message.new(role: :user, content: "Second"),
        ]

        input = provider.send(:format_new_input_messages, messages)

        assert_equal(1, input.size)
        assert_equal("user", input[0][:role])
        assert_equal("Second", input[0][:content])
      end

      def test_format_new_input_messages_with_system_messages
        provider = OpenAIWithResponses.new(@config)

        messages = [
          RubyLLM::Message.new(role: :assistant, content: "Response"),
          RubyLLM::Message.new(role: :system, content: "System instruction"),
        ]

        input = provider.send(:format_new_input_messages, messages)

        assert_equal(1, input.size)
        assert_equal("developer", input[0][:role])
        assert_equal("System instruction", input[0][:content])
      end

      def test_format_input_messages_with_assistant_empty_content
        provider = OpenAIWithResponses.new(@config)

        messages = [
          RubyLLM::Message.new(role: :user, content: "Hello"),
          RubyLLM::Message.new(role: :assistant, content: ""), # Empty content
          RubyLLM::Message.new(role: :user, content: "Again"),
        ]

        input = provider.send(:format_input_messages, messages)

        # Should have 2 user messages, skip empty assistant
        assert_equal(2, input.size)
        assert_equal("user", input[0][:role])
        assert_equal("user", input[1][:role])
      end

      def test_format_input_messages_with_assistant_nil_content
        provider = OpenAIWithResponses.new(@config)

        messages = [
          RubyLLM::Message.new(role: :user, content: "Hello"),
          RubyLLM::Message.new(role: :assistant, content: nil), # Nil content
          RubyLLM::Message.new(role: :user, content: "Again"),
        ]

        input = provider.send(:format_input_messages, messages)

        # Should have 2 user messages, skip nil assistant
        assert_equal(2, input.size)
      end

      def test_format_input_messages_includes_system_messages
        provider = OpenAIWithResponses.new(@config)

        messages = [
          RubyLLM::Message.new(role: :system, content: "System prompt"),
          RubyLLM::Message.new(role: :user, content: "Hello"),
        ]

        input = provider.send(:format_input_messages, messages)

        assert_equal(2, input.size)
        assert_equal("developer", input[0][:role])
        assert_equal("user", input[1][:role])
      end

      def test_extract_message_data_with_string_content
        provider = OpenAIWithResponses.new(@config)

        data = {
          "output" => [
            { "type" => "message", "content" => "Direct string content" },
          ],
        }

        message_data = provider.send(:extract_message_data, data)

        assert_equal("Direct string content", message_data["content"])
      end

      def test_extract_message_data_with_text_field
        provider = OpenAIWithResponses.new(@config)

        data = {
          "output" => [
            { "type" => "message", "text" => "Text field content" },
          ],
        }

        message_data = provider.send(:extract_message_data, data)

        assert_equal("Text field content", message_data["content"])
      end

      def test_extract_message_data_fallback_to_choices
        provider = OpenAIWithResponses.new(@config)

        data = {
          "choices" => [
            { "message" => { "content" => "Fallback content" } },
          ],
        }

        message_data = provider.send(:extract_message_data, data)

        assert_equal("Fallback content", message_data["content"])
      end

      def test_log_parse_error_with_agent_name
        provider = OpenAIWithResponses.new(@config)
        provider.agent_name = :test_agent

        # Mock LogStream
        events = []
        LogStream.stub(:emit, ->(entry) { events << entry }) do
          provider.send(:log_parse_error, "TestError", "Test message", "test body")
        end

        assert_equal(1, events.size)
        assert_equal("response_parse_error", events[0][:type])
        assert_equal(:test_agent, events[0][:agent])
        assert_equal("TestError", events[0][:error_class])
      end

      def test_log_parse_error_without_agent_name
        provider = OpenAIWithResponses.new(@config)

        # Should not raise error when agent_name is nil
        # Instead falls back to RubyLLM logger (we just verify no error is raised)
        # Suppress logger output during test
        capture_io do
          provider.send(:log_parse_error, "TestError", "Test message", "test body")
        end
        # Test passes if no exception was raised
      end

      def test_parse_completion_response_with_nil_body
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)
        provider.agent_name = :test_agent

        # Mock LogStream to capture event
        events = []
        LogStream.stub(:emit, ->(entry) { events << entry }) do
          mock_response = Struct.new(:body).new(nil)
          result = provider.send(:parse_completion_response, mock_response)

          assert_nil(result)
          assert_equal(1, events.size)
          assert_equal("response_parse_error", events[0][:type])
          assert_includes(events[0][:error_message], "nil response body")
        end
      end

      def test_parse_completion_response_with_no_method_error
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)
        provider.agent_name = :test_agent

        # Create a response that will trigger NoMethodError with "dig" in message
        mock_response = Struct.new(:body).new("string body")

        # Stub should_use_responses_api? to return true
        provider.stub(:should_use_responses_api?, true) do
          # Mock LogStream to capture event
          events = []
          LogStream.stub(:emit, ->(entry) { events << entry }) do
            result = provider.send(:parse_completion_response, mock_response)

            assert_nil(result)
            # Should have logged the error
            assert_operator(events.size, :>=, 1)
          end
        end
      end

      def test_response_id_not_captured_when_disabled
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)
        provider.instance_variable_set(:@disable_response_id, true)

        response_body = {
          "id" => "resp_should_not_capture",
          "output" => [
            { "type" => "message", "content" => [{ "type" => "output_text", "text" => "Hello" }] },
          ],
        }

        mock_response = Struct.new(:body).new(response_body)

        provider.send(:parse_responses_api_response, mock_response)

        # Should NOT capture response ID when disabled
        assert_nil(provider.instance_variable_get(:@last_response_id))
      end

      def test_render_responses_payload_with_expired_id_logs_debug
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        # Set an expired response ID
        provider.instance_variable_set(:@last_response_id, "resp_expired")
        provider.instance_variable_set(:@last_response_time, Time.now - 400) # Expired

        messages = [
          RubyLLM::Message.new(role: :user, content: "Hello"),
        ]

        model = RubyLLM::Models.find("gpt-5")

        # Should log about expired ID (we can't easily test logger output, but verify it doesn't crash)
        payload = provider.send(:render_responses_payload, messages, tools: {}, temperature: nil, model: model)

        # Should not use previous_response_id
        refute(payload.key?(:previous_response_id))
      end

      def test_render_responses_payload_with_no_previous_id_logs_first_turn
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        messages = [
          RubyLLM::Message.new(role: :user, content: "Hello"),
        ]

        model = RubyLLM::Models.find("gpt-5")

        payload = provider.send(:render_responses_payload, messages, tools: {}, temperature: nil, model: model)

        # Should not have previous_response_id
        refute(payload.key?(:previous_response_id))
        # Should have input
        assert(payload.key?(:input))
      end

      def test_extract_input_tokens_from_prompt_tokens
        provider = OpenAIWithResponses.new(@config)

        data = { "usage" => { "prompt_tokens" => 150 } }

        assert_equal(150, provider.send(:extract_input_tokens, data))
      end

      def test_extract_input_tokens_from_input_tokens
        provider = OpenAIWithResponses.new(@config)

        data = { "usage" => { "input_tokens" => 200 } }

        assert_equal(200, provider.send(:extract_input_tokens, data))
      end

      def test_extract_output_tokens_from_completion_tokens
        provider = OpenAIWithResponses.new(@config)

        data = { "usage" => { "completion_tokens" => 75 } }

        assert_equal(75, provider.send(:extract_output_tokens, data))
      end

      def test_extract_output_tokens_from_output_tokens
        provider = OpenAIWithResponses.new(@config)

        data = { "usage" => { "output_tokens" => 100 } }

        assert_equal(100, provider.send(:extract_output_tokens, data))
      end

      def test_parse_responses_api_response_with_non_hash_body
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)
        provider.agent_name = :test_agent

        mock_response = Struct.new(:body).new("not a hash")

        # Mock LogStream
        events = []
        LogStream.stub(:emit, ->(entry) { events << entry }) do
          result = provider.send(:parse_responses_api_response, mock_response)

          assert_nil(result)
          assert_equal(1, events.size)
          assert_includes(events[0][:error_message], "Expected response body to be Hash")
        end
      end

      def test_parse_responses_api_response_with_empty_hash
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        mock_response = Struct.new(:body).new({})

        result = provider.send(:parse_responses_api_response, mock_response)

        assert_nil(result)
      end

      def test_parse_responses_api_response_with_error_message
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        response_body = {
          "error" => {
            "message" => "API error occurred",
          },
        }

        mock_response = Struct.new(:body).new(response_body)

        error = assert_raises(RubyLLM::Error) do
          provider.send(:parse_responses_api_response, mock_response)
        end

        assert_includes(error.message, "API error occurred")
      end

      def test_extract_message_data_with_reasoning_items
        provider = OpenAIWithResponses.new(@config)

        data = {
          "output" => [
            { "type" => "reasoning", "reasoning" => "Internal thought process" },
            { "type" => "message", "content" => [{ "type" => "output_text", "text" => "Final answer" }] },
          ],
        }

        message_data = provider.send(:extract_message_data, data)

        # Should skip reasoning and only include message content
        assert_equal("Final answer", message_data["content"])
      end

      def test_extract_message_data_with_function_calls
        provider = OpenAIWithResponses.new(@config)

        data = {
          "output" => [
            {
              "type" => "function_call",
              "call_id" => "call_abc",
              "name" => "test_tool",
              "arguments" => { "arg" => "value" },
            },
          ],
        }

        message_data = provider.send(:extract_message_data, data)

        assert_equal(1, message_data["tool_calls"].size)
        assert_equal("call_abc", message_data["tool_calls"][0]["id"])
        assert_equal("test_tool", message_data["tool_calls"][0]["function"]["name"])
      end

      def test_extract_message_data_with_text_type_content
        provider = OpenAIWithResponses.new(@config)

        data = {
          "output" => [
            {
              "type" => "message",
              "content" => [
                { "type" => "text", "text" => "Text content" },
              ],
            },
          ],
        }

        message_data = provider.send(:extract_message_data, data)

        assert_equal("Text content", message_data["content"])
      end
    end
  end
end
