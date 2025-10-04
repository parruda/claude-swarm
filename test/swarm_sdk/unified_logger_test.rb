# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class UnifiedLoggerTest < Minitest::Test
    def setup
      @logger = UnifiedLogger.new
      @logs = []
      @logger.on_log { |log| @logs << log }
    end

    def test_initialization
      logger = UnifiedLogger.new

      assert_instance_of(UnifiedLogger, logger)
      assert_empty(logger.instance_variable_get(:@log_callbacks))
    end

    def test_on_log_registers_callback
      logger = UnifiedLogger.new
      callback_called = false

      logger.on_log { |_log| callback_called = true }

      assert_equal(1, logger.instance_variable_get(:@log_callbacks).size)

      # Trigger a log emission
      logger.emit(type: "test")

      assert(callback_called)
    end

    def test_on_log_registers_multiple_callbacks
      logger = UnifiedLogger.new
      call_count = 0

      logger.on_log { |_log| call_count += 1 }
      logger.on_log { |_log| call_count += 1 }
      logger.on_log { |_log| call_count += 1 }

      logger.emit(type: "test")

      assert_equal(3, call_count)
    end

    def test_emit_adds_timestamp
      @logger.emit(type: "test_event", data: "value")

      assert_equal(1, @logs.size)
      log = @logs.first

      assert(log.key?(:timestamp))
      assert_match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/, log[:timestamp])
    end

    def test_emit_includes_all_data
      @logger.emit(
        type: "test_event",
        agent: "test_agent",
        data: "value",
        nested: { key: "value" },
      )

      log = @logs.first

      assert_equal("test_event", log[:type])
      assert_equal("test_agent", log[:agent])
      assert_equal("value", log[:data])
      assert_equal({ key: "value" }, log[:nested])
    end

    def test_emit_compacts_nil_values
      @logger.emit(
        type: "test",
        present: "value",
        absent: nil,
      )

      log = @logs.first

      assert(log.key?(:present))
      refute(log.key?(:absent))
    end

    def test_emit_calls_all_callbacks
      logs1 = []
      logs2 = []

      @logger.on_log { |log| logs1 << log }
      @logger.on_log { |log| logs2 << log }

      @logger.emit(type: "test")

      # First callback was registered in setup
      assert_equal(1, @logs.size)
      assert_equal(1, logs1.size)
      assert_equal(1, logs2.size)
    end

    def test_attach_to_chat_returns_chat
      mock_chat = create_mock_chat

      result = @logger.attach_to_chat(mock_chat, agent_name: "test_agent")

      assert_equal(mock_chat, result)
    end

    def test_attach_to_chat_registers_on_new_message_callback
      mock_chat = create_mock_chat

      @logger.attach_to_chat(mock_chat, agent_name: "test_agent")

      # Trigger on_new_message callback
      mock_chat.trigger_new_message

      assert_equal(1, @logs.size)
      assert_equal("llm_request", @logs.first[:type])
    end

    def test_llm_request_log_structure
      mock_chat = create_mock_chat
      @logger.attach_to_chat(mock_chat, agent_name: "backend", metadata: { session_id: "123" })

      mock_chat.trigger_new_message

      log = @logs.first

      assert_equal("llm_request", log[:type])
      assert_equal("backend", log[:agent])
      assert_equal("gpt-5", log[:model])
      assert_equal("openai", log[:provider])
      assert_equal(2, log[:message_count])
      assert_equal([:test_tool], log[:tools])
      assert_equal({ session_id: "123" }, log[:metadata])
      assert(log.key?(:timestamp))
    end

    def test_llm_request_logged_only_once_per_message
      mock_chat = create_mock_chat
      @logger.attach_to_chat(mock_chat, agent_name: "test_agent")

      mock_chat.trigger_new_message
      mock_chat.trigger_new_message
      mock_chat.trigger_new_message

      llm_requests = @logs.select { |log| log[:type] == "llm_request" }

      assert_equal(1, llm_requests.size)
    end

    def test_llm_response_log_with_content
      mock_chat = create_mock_chat
      @logger.attach_to_chat(mock_chat, agent_name: "backend")

      message = create_mock_message(content: "Response text", tool_calls: nil)
      mock_chat.trigger_end_message(message)

      log = @logs.first

      assert_equal("llm_response", log[:type])
      assert_equal("backend", log[:agent])
      assert_equal("gpt-5", log[:model])
      assert_equal("Response text", log[:content])
      assert_nil(log[:tool_calls])
      assert_equal("stop", log[:finish_reason])

      usage = log[:usage]

      assert_equal(100, usage[:input_tokens])
      assert_equal(50, usage[:output_tokens])
      assert_equal(150, usage[:total_tokens])
    end

    def test_llm_response_log_with_tool_calls
      mock_chat = create_mock_chat
      @logger.attach_to_chat(mock_chat, agent_name: "backend")

      tool_call = create_mock_tool_call(id: "call_123", name: "test_tool", arguments: { arg: "value" })
      message = create_mock_message(content: nil, tool_calls: { "call_123" => tool_call })

      mock_chat.trigger_end_message(message)

      log = @logs.first

      assert_equal("llm_response", log[:type])
      assert_equal("tool_calls", log[:finish_reason])
      assert_equal(1, log[:tool_calls].size)

      tool_call_log = log[:tool_calls].first

      assert_equal("call_123", tool_call_log[:id])
      assert_equal("test_tool", tool_call_log[:name])
      assert_equal({ arg: "value" }, tool_call_log[:arguments])
    end

    def test_tool_call_log_structure
      mock_chat = create_mock_chat
      @logger.attach_to_chat(mock_chat, agent_name: "backend")

      tool_call = create_mock_tool_call(id: "call_456", name: "Read", arguments: { file: "test.rb" })
      mock_chat.trigger_tool_call(tool_call)

      log = @logs.first

      assert_equal("tool_call", log[:type])
      assert_equal("backend", log[:agent])
      assert_equal("call_456", log[:tool_call_id])
      assert_equal("Read", log[:tool])
      assert_equal({ file: "test.rb" }, log[:arguments])
    end

    def test_tool_result_log_structure
      mock_chat = create_mock_chat
      @logger.attach_to_chat(mock_chat, agent_name: "backend")

      message = create_mock_tool_result_message(
        tool_call_id: "call_789",
        content: "File contents",
      )

      mock_chat.trigger_end_message(message)

      log = @logs.first

      assert_equal("tool_result", log[:type])
      assert_equal("backend", log[:agent])
      assert_equal("call_789", log[:tool_call_id])
      assert_equal("File contents", log[:result])
    end

    def test_serialize_result_with_string
      result = @logger.send(:serialize_result, "test string")

      assert_equal("test string", result)
    end

    def test_serialize_result_with_hash
      result = @logger.send(:serialize_result, { key: "value" })

      assert_equal({ key: "value" }, result)
    end

    def test_serialize_result_with_array
      result = @logger.send(:serialize_result, [1, 2, 3])

      assert_equal([1, 2, 3], result)
    end

    def test_serialize_result_with_other_object
      obj = Object.new
      def obj.to_s
        "custom object"
      end

      result = @logger.send(:serialize_result, obj)

      assert_equal("custom object", result)
    end

    def test_format_tool_calls_with_nil
      result = @logger.send(:format_tool_calls, nil)

      assert_nil(result)
    end

    def test_format_tool_calls_with_empty_hash
      result = @logger.send(:format_tool_calls, {})

      assert_empty(result)
    end

    def test_format_tool_calls_with_tool_calls
      tool_call1 = create_mock_tool_call(id: "1", name: "Read", arguments: { file: "a.rb" })
      tool_call2 = create_mock_tool_call(id: "2", name: "Edit", arguments: { file: "b.rb" })

      result = @logger.send(:format_tool_calls, { "1" => tool_call1, "2" => tool_call2 })

      assert_equal(2, result.size)
      assert_equal("1", result[0][:id])
      assert_equal("Read", result[0][:name])
      assert_equal("2", result[1][:id])
      assert_equal("Edit", result[1][:name])
    end

    def test_calculate_cost_with_tokens
      message = create_mock_message_with_model_info(
        model_id: "gpt-4",
        input_tokens: 1000,
        output_tokens: 500,
      )

      # Mock RubyLLM.models.find to return model info
      mock_model_info = Minitest::Mock.new
      mock_model_info.expect(:input_price_per_million, 10.0)
      mock_model_info.expect(:output_price_per_million, 30.0)

      RubyLLM.models.stub(:find, mock_model_info) do
        cost = @logger.send(:calculate_cost, message)

        assert_in_delta(0.01, cost[:input_cost], 0.001)   # 1000 / 1_000_000 * 10
        assert_in_delta(0.015, cost[:output_cost], 0.001) # 500 / 1_000_000 * 30
        assert_in_delta(0.025, cost[:total_cost], 0.001)
      end

      mock_model_info.verify
    end

    def test_calculate_cost_without_tokens_returns_zero
      message = create_mock_message(input_tokens: nil, output_tokens: nil)

      cost = @logger.send(:calculate_cost, message)

      assert_in_delta(0.0, cost[:input_cost])
      assert_in_delta(0.0, cost[:output_cost])
      assert_in_delta(0.0, cost[:total_cost])
    end

    def test_calculate_cost_with_unknown_model_returns_zero
      message = create_mock_message_with_model_info(
        model_id: "unknown-model",
        input_tokens: 1000,
        output_tokens: 500,
      )

      RubyLLM.models.stub(:find, nil) do
        cost = @logger.send(:calculate_cost, message)

        assert_in_delta(0.0, cost[:input_cost])
        assert_in_delta(0.0, cost[:output_cost])
        assert_in_delta(0.0, cost[:total_cost])
      end
    end

    def test_zero_cost
      cost = @logger.send(:zero_cost)

      assert_in_delta(0.0, cost[:input_cost])
      assert_in_delta(0.0, cost[:output_cost])
      assert_in_delta(0.0, cost[:total_cost])
    end

    private

    def create_mock_chat
      mock_model = Struct.new(:id, :provider).new("gpt-5", "openai")

      mock_chat_class = Struct.new(:callbacks, :model, :messages, :tools, keyword_init: true) do
        def on_new_message(&block)
          callbacks[:new_message] << block
          self
        end

        def on_end_message(&block)
          callbacks[:end_message] << block
          self
        end

        def on_tool_call(&block)
          callbacks[:tool_call] << block
          self
        end

        def on_tool_result(&block)
          callbacks[:tool_result] << block
          self
        end

        def trigger_new_message
          callbacks[:new_message].each(&:call)
        end

        def trigger_end_message(message)
          callbacks[:end_message].each { |cb| cb.call(message) }
        end

        def trigger_tool_call(tool_call)
          callbacks[:tool_call].each { |cb| cb.call(tool_call) }
        end

        def trigger_tool_result(result)
          callbacks[:tool_result].each { |cb| cb.call(result) }
        end
      end

      mock_chat_class.new(
        callbacks: { new_message: [], end_message: [], tool_call: [], tool_result: [] },
        model: mock_model,
        messages: [{}, {}], # 2 messages
        tools: { test_tool: {} },
      )
    end

    def create_mock_message(content: nil, tool_calls: nil, input_tokens: 100, output_tokens: 50)
      Struct.new(
        :role,
        :content,
        :tool_calls,
        :model_id,
        :input_tokens,
        :output_tokens,
        keyword_init: true,
      ) do
        def tool_call?
          !tool_calls.nil?
        end
      end.new(
        role: :assistant,
        content: content,
        tool_calls: tool_calls,
        model_id: "gpt-5",
        input_tokens: input_tokens,
        output_tokens: output_tokens,
      )
    end

    def create_mock_message_with_model_info(model_id:, input_tokens:, output_tokens:)
      Struct.new(:model_id, :input_tokens, :output_tokens, keyword_init: true).new(
        model_id: model_id,
        input_tokens: input_tokens,
        output_tokens: output_tokens,
      )
    end

    def create_mock_tool_result_message(tool_call_id:, content:)
      Struct.new(:role, :tool_call_id, :content, keyword_init: true).new(
        role: :tool,
        tool_call_id: tool_call_id,
        content: content,
      )
    end

    def create_mock_tool_call(id:, name:, arguments:)
      Struct.new(:id, :name, :arguments, keyword_init: true).new(
        id: id,
        name: name,
        arguments: arguments,
      )
    end
  end
end
