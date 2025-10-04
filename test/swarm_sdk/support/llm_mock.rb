# frozen_string_literal: true

module SwarmSDK
  class LLMMock
    attr_reader :call_history, :chat_instances

    def initialize
      @responses = []
      @call_history = []
      @chat_instances = []
    end

    def add_response(content: nil, tool_calls: [], finish_reason: "stop", usage: {})
      @responses << {
        content: content,
        tool_calls: tool_calls,
        finish_reason: finish_reason,
        usage: usage,
      }
    end

    def chat(model:, **options)
      chat_instance = ChatMock.new(self, model, options)
      @chat_instances << chat_instance
      chat_instance
    end

    def next_response
      @responses.shift || default_response
    end

    def record_call(method, **params)
      @call_history << { method: method, params: params, timestamp: Time.now }
    end

    private

    def default_response
      {
        content: "Default LLM response",
        tool_calls: [],
        finish_reason: "stop",
        usage: { input_tokens: 10, output_tokens: 5 },
      }
    end

    class ChatMock
      attr_reader :messages, :model, :options, :parent_mock

      def initialize(parent_mock, model, options)
        @parent_mock = parent_mock
        @model = model
        @options = options
        @messages = []
      end

      def ask(prompt, **call_options)
        @parent_mock.record_call(:ask, prompt: prompt, options: call_options)
        @messages << { role: "user", content: prompt }

        response_data = @parent_mock.next_response

        @messages << { role: "assistant", content: response_data[:content] } if response_data[:content]

        ResponseMock.new(response_data)
      end

      def with_instructions(instructions)
        @options[:instructions] = instructions
        self
      end

      def with_temperature(temperature)
        @options[:temperature] = temperature
        self
      end

      def with_max_tokens(max_tokens)
        @options[:max_tokens] = max_tokens
        self
      end

      def add_message(message)
        @messages << message
      end

      def reset_messages!
        @messages.clear
      end
    end

    class ResponseMock
      attr_reader :content, :tool_calls, :finish_reason, :usage

      def initialize(data)
        @content = data[:content]
        @tool_calls = data[:tool_calls]
        @finish_reason = data[:finish_reason]
        @usage = data[:usage] || {}
      end

      def input_tokens
        @usage[:input_tokens] || 0
      end

      def output_tokens
        @usage[:output_tokens] || 0
      end

      def model_id
        "mock-model"
      end
    end
  end
end
