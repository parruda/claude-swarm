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

    # Calculate total cost across all LLM responses
    #
    # Cost accumulation works as follows:
    # - Input cost: The LAST response's input_cost already includes the cost for the
    #   full conversation history (all previous messages + current context)
    # - Output cost: Each response generates NEW tokens, so we SUM all output_costs
    # - Total = Last input_cost + Sum of all output_costs
    #
    # IMPORTANT: Do NOT sum total_cost across all entries - that would count
    # input costs multiple times since each call includes the full history!
    def total_cost
      entries_with_usage = @logs.select { |entry| entry.dig(:usage, :total_cost) }
      return 0.0 if entries_with_usage.empty?

      # Last entry's input cost (includes full conversation history)
      last_input_cost = entries_with_usage.last.dig(:usage, :input_cost) || 0.0

      # Sum all output costs (each response generates new tokens)
      total_output_cost = entries_with_usage.sum { |entry| entry.dig(:usage, :output_cost) || 0.0 }

      last_input_cost + total_output_cost
    end

    # Get total tokens from the last LLM response with cumulative tracking
    #
    # Token accumulation works as follows:
    # - Input tokens: Each API call sends the full conversation history, so the latest
    #   response's cumulative_input_tokens already represents the full context
    # - Output tokens: Each response generates new tokens, cumulative_output_tokens sums them
    # - The cumulative_total_tokens in the last response already does this correctly
    #
    # IMPORTANT: Do NOT sum total_tokens across all log entries - that would count
    # input tokens multiple times since each call includes the full history!
    def total_tokens
      last_entry = @logs.reverse.find { |entry| entry.dig(:usage, :cumulative_total_tokens) }
      last_entry&.dig(:usage, :cumulative_total_tokens) || 0
    end

    # Get list of all agents involved in execution
    def agents_involved
      @logs.map { |entry| entry[:agent] }.compact.uniq.map(&:to_sym)
    end

    # Count total LLM requests made
    # Each LLM API call produces either agent_step (tool calls) or agent_stop (final answer)
    def llm_requests
      @logs.count { |entry| entry[:type] == "agent_step" || entry[:type] == "agent_stop" }
    end

    # Count total tool calls made
    def tool_calls_count
      @logs.count { |entry| entry[:type] == "tool_call" }
    end
  end
end
