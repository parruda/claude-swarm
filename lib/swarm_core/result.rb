# frozen_string_literal: true

module SwarmCore
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
  end
end
