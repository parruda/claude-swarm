# frozen_string_literal: true

module SwarmSDK
  class Result
    attr_reader :content, :agent, :cost, :tokens, :duration, :logs, :error, :metadata

    def initialize(content: nil, agent:, cost: 0.0, tokens: {}, duration: 0.0, logs: [], error: nil, metadata: {})
      @content = content
      @agent = agent
      @cost = cost
      @tokens = tokens
      @duration = duration
      @logs = logs
      @error = error
      @metadata = metadata
    end

    def success?
      @error.nil?
    end

    def failure?
      !success?
    end

    def to_h
      {
        content: @content,
        agent: @agent,
        cost: @cost,
        tokens: @tokens,
        duration: @duration,
        success: success?,
        error: @error&.message,
        metadata: @metadata,
      }.compact
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    # Aggregate total cost from all LLM responses in logs
    def total_cost
      @logs.sum { |entry| entry.dig(:usage, :total_cost) || 0.0 }
    end

    # Aggregate total tokens from all LLM responses in logs
    def total_tokens
      @logs.sum { |entry| entry.dig(:usage, :total_tokens) || 0 }
    end

    # Get list of all agents involved in execution
    def agents_involved
      @logs.map { |entry| entry[:agent] }.compact.uniq.map(&:to_sym)
    end

    # Count total LLM requests made
    def llm_requests
      @logs.count { |entry| entry[:type] == "llm_response" }
    end

    # Count total tool calls made
    def tool_calls_count
      @logs.count { |entry| entry[:type] == "tool_call" }
    end
  end
end
