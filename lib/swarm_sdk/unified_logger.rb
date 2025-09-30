# frozen_string_literal: true

module SwarmSDK
  class UnifiedLogger
    def initialize
      @log_callbacks = []
    end

    def on_log(&block)
      @log_callbacks << block
    end

    def attach_to_chat(chat, agent_name:, metadata: {})
      request_logged = false
      tool_executions = []

      chat.on_new_message do
        unless request_logged
          log_llm_request(
            agent: agent_name,
            model: chat.model.id,
            provider: chat.model.provider,
            message_count: chat.messages.size,
            tools: chat.tools.keys,
            metadata: metadata,
          )
          request_logged = true
        end
      end

      chat.on_tool_call do |tool_call|
        log_tool_call(
          agent: agent_name,
          tool_call: tool_call,
          metadata: metadata,
        )
      end

      chat.on_tool_result do |result|
        tool_executions << {
          result: serialize_result(result),
          completed_at: Time.now.utc.iso8601,
        }
      end

      chat.on_end_message do |message|
        next unless message

        case message.role
        when :assistant
          log_llm_response(
            agent: agent_name,
            message: message,
            tool_executions: tool_executions,
            metadata: metadata,
          )
          tool_executions.clear if message.tool_call?
        when :tool
          log_tool_result(
            agent: agent_name,
            message: message,
            metadata: metadata,
          )
        end
      end

      chat
    end

    def emit(**data)
      log_entry = data.merge(timestamp: Time.now.utc.iso8601)
      log_entry.compact!

      @log_callbacks.each do |callback|
        callback.call(log_entry)
      end
    end

    private

    def log_llm_request(agent:, model:, provider:, message_count:, tools:, metadata:)
      emit(
        type: "llm_request",
        agent: agent,
        model: model,
        provider: provider,
        message_count: message_count,
        tools: tools,
        metadata: metadata,
      )
    end

    def log_llm_response(agent:, message:, tool_executions:, metadata:)
      emit(
        type: "llm_response",
        agent: agent,
        model: message.model_id,
        content: message.content,
        tool_calls: message.tool_call? ? format_tool_calls(message.tool_calls) : nil,
        finish_reason: message.tool_call? ? "tool_calls" : "stop",
        usage: {
          input_tokens: message.input_tokens,
          output_tokens: message.output_tokens,
          total_tokens: (message.input_tokens || 0) + (message.output_tokens || 0),
        },
        tool_executions: tool_executions.empty? ? nil : tool_executions,
        metadata: metadata,
      )
    end

    def log_tool_call(agent:, tool_call:, metadata:)
      emit(
        type: "tool_call",
        agent: agent,
        tool_call_id: tool_call.id,
        tool: tool_call.name,
        arguments: tool_call.arguments,
        metadata: metadata,
      )
    end

    def log_tool_result(agent:, message:, metadata:)
      emit(
        type: "tool_result",
        agent: agent,
        tool_call_id: message.tool_call_id,
        result: serialize_result(message.content),
        metadata: metadata,
      )
    end

    def format_tool_calls(tool_calls_hash)
      return unless tool_calls_hash

      tool_calls_hash.map do |_id, tc|
        {
          id: tc.id,
          name: tc.name,
          arguments: tc.arguments,
        }
      end
    end

    def serialize_result(result)
      case result
      when String then result
      when Hash, Array then result
      else
        result.to_s
      end
    end
  end
end
