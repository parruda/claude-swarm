# frozen_string_literal: true

module SwarmSDK
  # AgentChat extends RubyLLM::Chat to enable parallel agent-to-agent tool calling
  # with two-level rate limiting to prevent API quota exhaustion.
  #
  # ## Rate Limiting Strategy
  #
  # In hierarchical agent trees, unlimited parallelism can cause exponential growth:
  #   Main → 10 agents → 100 agents → 1,000 agents = API meltdown!
  #
  # Solution: Two-level semaphore system
  # 1. **Global semaphore** - Total concurrent LLM calls across entire swarm
  # 2. **Local semaphore** - Max concurrent tool calls for this specific agent
  #
  # Example:
  #   global_semaphore = Async::Semaphore.new(50)  # Max 50 LLM calls total
  #
  #   chat = AgentChat.new(
  #     model: 'claude-sonnet-4',
  #     global_semaphore: global_semaphore,   # Shared across all agents
  #     max_concurrent_tools: 10               # This agent can call 10 tools at once
  #   )
  #
  #   response = chat.ask("Coordinate team")
  #   # If agent calls 20 sub-agents:
  #   # - 10 execute immediately (local limit)
  #   # - 10 wait in queue
  #   # - Global limit ensures total swarm doesn't exceed 50 concurrent calls
  #
  class AgentChat < RubyLLM::Chat
    # Initialize AgentChat with rate limiting
    #
    # @param model [String] LLM model identifier
    # @param global_semaphore [Async::Semaphore, nil] Shared across all agents
    # @param max_concurrent_tools [Integer, nil] Max concurrent tool calls for this agent
    # @param base_url [String, nil] Custom API endpoint (creates isolated context)
    def initialize(model:, global_semaphore: nil, max_concurrent_tools: nil, base_url: nil, **options)
      # Create isolated context if custom base_url specified
      if base_url
        context = RubyLLM.context do |config|
          # Detect provider from model name and set appropriate base URL and API key
          if model.start_with?("gpt-", "o1-", "o3-")
            config.openai_api_base = base_url
            config.openai_api_key = ENV["OPENAI_API_KEY"] if ENV["OPENAI_API_KEY"]
          elsif model.start_with?("claude-")
            config.anthropic_api_base = base_url
            config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"] if ENV["ANTHROPIC_API_KEY"]
          else
            # Default to OpenAI-compatible
            config.openai_api_base = base_url
            config.openai_api_key = ENV["OPENAI_API_KEY"] if ENV["OPENAI_API_KEY"]
          end
        end
        super(model: model, context: context, **options)
      else
        super(model: model, **options)
      end

      @global_semaphore = global_semaphore
      @local_semaphore = max_concurrent_tools ? Async::Semaphore.new(max_concurrent_tools) : nil
    end

    private

    # Override to execute multiple tool calls in parallel with rate limiting.
    #
    # RubyLLM's default implementation executes tool calls one at a time. This
    # override uses Async to execute all tool calls concurrently, with semaphores
    # to prevent API quota exhaustion.
    #
    # @param response [RubyLLM::Message] LLM response with tool calls
    # @param block [Proc] Optional block passed through to complete
    # @return [RubyLLM::Message] Final response when loop completes
    def handle_tool_calls(response, &block)
      # Single tool call: use default sequential execution (no overhead)
      return super if response.tool_calls.size == 1

      # Multiple tool calls: execute in parallel with rate limiting
      halt_result = nil

      results = Async do
        response.tool_calls.map do |_id, tool_call|
          Async do
            # Acquire semaphores (queues if limit reached)
            acquire_semaphores do
              @on[:tool_call]&.call(tool_call)
              result = execute_tool(tool_call)
              @on[:tool_result]&.call(result)
              { tool_call: tool_call, result: result }
            end
          end
        end.map(&:wait)
      end.wait

      # Add all tool results to conversation
      results.each do |data|
        content = data[:result].is_a?(RubyLLM::Content) ? data[:result] : data[:result].to_s
        message = add_message(
          role: :tool,
          content: content,
          tool_call_id: data[:tool_call].id,
        )
        @on[:end_message]&.call(message)

        halt_result = data[:result] if data[:result].is_a?(RubyLLM::Tool::Halt)
      end

      # Continue automatic loop (recursive call to complete)
      halt_result || complete(&block)
    end

    # Acquire both global and local semaphores (if configured).
    #
    # Semaphores queue requests when limits are reached, ensuring graceful
    # degradation instead of API errors.
    #
    # Order matters: acquire global first (broader scope), then local
    def acquire_semaphores(&block)
      if @global_semaphore && @local_semaphore
        # Both limits: acquire global first, then local
        @global_semaphore.acquire do
          @local_semaphore.acquire(&block)
        end
      elsif @global_semaphore
        # Only global limit
        @global_semaphore.acquire(&block)
      elsif @local_semaphore
        # Only local limit
        @local_semaphore.acquire(&block)
      else
        # No limits: execute immediately
        yield
      end
    end
  end
end
