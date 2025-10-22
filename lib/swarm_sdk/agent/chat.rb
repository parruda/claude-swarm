# frozen_string_literal: true

module SwarmSDK
  module Agent
    # Chat extends RubyLLM::Chat to enable parallel agent-to-agent tool calling
    # with two-level rate limiting to prevent API quota exhaustion
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
    # ## Architecture
    #
    # This class is now organized with clear separation of concerns:
    # - Core (this file): Initialization, provider setup, rate limiting, parallel execution
    # - SystemReminderInjector: First message reminders, TodoWrite reminders
    # - LoggingHelpers: Tool call formatting, result serialization
    # - ContextTracker: Logging callbacks, delegation tracking
    # - HookIntegration: Hook system integration (wraps tool execution with hooks)
    class Chat < RubyLLM::Chat
      # Include logging helpers for tool call formatting
      include LoggingHelpers

      # Include hook integration for user_prompt hooks and hook trigger methods
      # This module overrides ask() to inject user_prompt hooks
      # and provides trigger methods for pre/post tool use hooks
      include HookIntegration

      # Register custom provider for responses API support
      # This is done once at class load time
      unless RubyLLM::Provider.providers.key?(:openai_with_responses)
        RubyLLM::Provider.register(:openai_with_responses, SwarmSDK::Providers::OpenAIWithResponses)
      end

      # Initialize AgentChat with rate limiting
      #
      # @param definition [Hash] Agent definition containing all configuration
      # @param global_semaphore [Async::Semaphore, nil] Shared across all agents (not part of definition)
      # @param options [Hash] Additional options to pass to RubyLLM::Chat
      # @raise [ArgumentError] If provider doesn't support custom base_url or provider not specified with base_url
      def initialize(definition:, global_semaphore: nil, **options)
        # Extract configuration from definition
        model = definition[:model]
        provider = definition[:provider]
        context_window = definition[:context_window]
        max_concurrent_tools = definition[:max_concurrent_tools]
        base_url = definition[:base_url]
        api_version = definition[:api_version]
        timeout = definition[:timeout] || Definition::DEFAULT_TIMEOUT
        assume_model_exists = definition[:assume_model_exists]
        system_prompt = definition[:system_prompt]
        parameters = definition[:parameters]
        headers = definition[:headers]

        # Create isolated context if custom base_url or timeout specified
        if base_url || timeout != Definition::DEFAULT_TIMEOUT
          # Provider is required when using custom base_url
          raise ArgumentError, "Provider must be specified when base_url is set" if base_url && !provider

          # Determine actual provider to use
          actual_provider = determine_provider(provider, base_url, api_version)
          RubyLLM.logger.debug("SwarmSDK Agent::Chat: Using provider '#{actual_provider}' (requested='#{provider}', api_version='#{api_version}')")

          context = build_custom_context(provider: provider, base_url: base_url, timeout: timeout)

          # Use assume_model_exists to bypass model validation for custom endpoints
          # Default to true when base_url is set, false otherwise (unless explicitly specified)
          assume_model_exists = base_url ? true : false if assume_model_exists.nil?

          super(model: model, provider: actual_provider, assume_model_exists: assume_model_exists, context: context, **options)

          # Configure custom provider after creation (RubyLLM doesn't support custom init params)
          if actual_provider == :openai_with_responses && api_version == "v1/responses"
            configure_responses_api_provider
          end
        elsif provider
          # No custom base_url or timeout: use RubyLLM's defaults (with optional provider override)
          assume_model_exists = false if assume_model_exists.nil?
          super(model: model, provider: provider, assume_model_exists: assume_model_exists, **options)
        else
          # No custom base_url, timeout, or provider: use RubyLLM's defaults
          assume_model_exists = false if assume_model_exists.nil?
          super(model: model, assume_model_exists: assume_model_exists, **options)
        end

        # Rate limiting semaphores
        @global_semaphore = global_semaphore
        @local_semaphore = max_concurrent_tools ? Async::Semaphore.new(max_concurrent_tools) : nil
        @explicit_context_window = context_window

        # Track TodoWrite usage for periodic reminders
        @last_todowrite_message_index = nil

        # Agent context for logging (set via setup_context)
        @agent_context = nil

        # Context tracker (created after agent_context is set)
        @context_tracker = nil

        # Track which tools are immutable (cannot be removed by skill swapping)
        # Default: Think, Clock, and TodoWrite are immutable utilities
        # SwarmMemory will mark memory tools as immutable when LoadSkill is registered
        @immutable_tool_names = Set.new(["Think", "Clock", "TodoWrite"])

        # Track active skill (only used if memory enabled)
        @active_skill_path = nil

        # Try to fetch real model info for accurate context tracking
        # This searches across ALL providers, so it works even when using proxies
        # (e.g., Claude model through OpenAI-compatible proxy)
        fetch_real_model_info(model)

        # Configure system prompt, parameters, and headers after parent initialization
        with_instructions(system_prompt) if system_prompt
        configure_parameters(parameters)
        configure_headers(headers)
      end

      # Setup agent context
      #
      # Sets the agent context for this chat, enabling delegation tracking.
      # This is always called, regardless of whether logging is enabled.
      #
      # @param context [Agent::Context] Agent context for this chat
      # @return [void]
      def setup_context(context)
        @agent_context = context
        @context_tracker = ContextTracker.new(self, context)
      end

      # Setup logging callbacks
      #
      # This configures the chat to emit log events via LogStream.
      # Should only be called when LogStream.emitter is set.
      #
      # @return [void]
      def setup_logging
        raise StateError, "Agent context not set. Call setup_context first." unless @agent_context

        @context_tracker.setup_logging
      end

      # Emit model lookup warning if one occurred during initialization
      #
      # If a model wasn't found in the registry during initialization, this will
      # emit a proper JSON log event through LogStream.
      #
      # @param agent_name [Symbol, String] The agent name for logging context
      def emit_model_lookup_warning(agent_name)
        return unless @model_lookup_error

        LogStream.emit(
          type: "model_lookup_warning",
          agent: agent_name,
          model: @model_lookup_error[:model],
          error_message: @model_lookup_error[:error_message],
          suggestions: @model_lookup_error[:suggestions].map { |s| { id: s.id, name: s.name, context_window: s.context_window } },
        )
      end

      # Mark tools as immutable (cannot be removed by skill swapping)
      #
      # This is called by SwarmMemory when LoadSkill is registered to mark
      # all memory tools as immutable. SwarmSDK doesn't need to know about
      # memory tools - this allows dynamic configuration at runtime.
      #
      # @param tool_names [Array<String>] Tool names to mark as immutable
      # @return [void]
      def mark_tools_immutable(*tool_names)
        @immutable_tool_names.merge(tool_names.flatten.map(&:to_s))
      end

      # Remove all mutable tools (keeps immutable tools)
      #
      # Used by LoadSkill to swap tools. Only works if called from a tool
      # that has been given access to the chat instance.
      #
      # @return [void]
      def remove_mutable_tools
        @tools.select! { |tool| @immutable_tool_names.include?(tool.name) }
      end

      # Add a tool instance dynamically
      #
      # Used by LoadSkill to add skill-required tools after removing mutable tools.
      # This is just a convenience wrapper around with_tool.
      #
      # @param tool_instance [RubyLLM::Tool] Tool to add
      # @return [void]
      def add_tool(tool_instance)
        with_tool(tool_instance)
      end

      # Mark skill as loaded (tracking for debugging/logging)
      #
      # Called by LoadSkill after successfully swapping tools.
      # This can be used for logging or debugging purposes.
      #
      # @param file_path [String] Path to loaded skill
      # @return [void]
      def mark_skill_loaded(file_path)
        @active_skill_path = file_path
      end

      # Check if a skill is currently loaded
      #
      # @return [Boolean] True if a skill has been loaded
      def skill_loaded?
        !@active_skill_path.nil?
      end

      # Override ask to inject system reminders and periodic TodoWrite reminders
      #
      # Note: This is called BEFORE HookIntegration#ask (due to module include order),
      # so HookIntegration will wrap this and inject user_prompt hooks.
      #
      # @param prompt [String] User prompt
      # @param options [Hash] Additional options to pass to complete
      # @return [RubyLLM::Message] LLM response
      def ask(prompt, **options)
        # Check if this is the first user message
        if SystemReminderInjector.first_message?(self)
          # Manually construct the first message sequence with system reminders
          SystemReminderInjector.inject_first_message_reminders(self, prompt)

          # Trigger user_prompt hook manually since we're bypassing the normal ask flow
          if @hook_executor
            hook_result = trigger_user_prompt(prompt)

            # Check if hook halted execution
            if hook_result[:halted]
              # Return a halted message instead of calling LLM
              return RubyLLM::Message.new(
                role: :assistant,
                content: hook_result[:halt_message],
                model_id: model.id,
              )
            end

            # NOTE: We ignore modified_prompt for first message since reminders already injected
          end

          # Call complete to get LLM response
          complete(**options)
        else
          # Inject periodic TodoWrite reminder if needed
          if SystemReminderInjector.should_inject_todowrite_reminder?(self, @last_todowrite_message_index)
            add_message(role: :user, content: SystemReminderInjector::TODOWRITE_PERIODIC_REMINDER)
            # Update tracking
            @last_todowrite_message_index = SystemReminderInjector.find_last_todowrite_index(self)
          end

          # Normal ask behavior for subsequent messages
          # This calls super which goes to HookIntegration's ask override
          super(prompt, **options)
        end
      end

      # Override handle_tool_calls to execute multiple tool calls in parallel with rate limiting.
      #
      # RubyLLM's default implementation executes tool calls one at a time. This
      # override uses Async to execute all tool calls concurrently, with semaphores
      # to prevent API quota exhaustion. Hooks are integrated via HookIntegration module.
      #
      # @param response [RubyLLM::Message] LLM response with tool calls
      # @param block [Proc] Optional block passed through to complete
      # @return [RubyLLM::Message] Final response when loop completes
      def handle_tool_calls(response, &block)
        # Single tool call: sequential execution with hooks
        if response.tool_calls.size == 1
          tool_call = response.tool_calls.values.first

          # Handle pre_tool_use hook (skip for delegation tools)
          unless delegation_tool_call?(tool_call)
            # Trigger pre_tool_use hook (can block or provide custom result)
            pre_result = trigger_pre_tool_use(tool_call)

            # Handle finish_agent marker
            if pre_result[:finish_agent]
              message = RubyLLM::Message.new(
                role: :assistant,
                content: pre_result[:custom_result],
                model_id: model.id,
              )
              # Set custom finish reason before triggering on_end_message
              @context_tracker.finish_reason_override = "finish_agent" if @context_tracker
              # Trigger on_end_message to ensure agent_stop event is emitted
              @on[:end_message]&.call(message)
              return message
            end

            # Handle finish_swarm marker
            if pre_result[:finish_swarm]
              return { __finish_swarm__: true, message: pre_result[:custom_result] }
            end

            # Handle blocked execution
            unless pre_result[:proceed]
              content = pre_result[:custom_result] || "Tool execution blocked by hook"
              message = add_message(
                role: :tool,
                content: content,
                tool_call_id: tool_call.id,
              )
              @on[:end_message]&.call(message)
              return complete(&block)
            end
          end

          # Execute tool
          @on[:tool_call]&.call(tool_call)

          result = execute_tool_with_error_handling(tool_call)

          @on[:tool_result]&.call(result)

          # Trigger post_tool_use hook (skip for delegation tools)
          unless delegation_tool_call?(tool_call)
            result = trigger_post_tool_use(result, tool_call: tool_call)
          end

          # Check for finish markers from hooks
          if result.is_a?(Hash)
            if result[:__finish_agent__]
              # Finish this agent with the provided message
              message = RubyLLM::Message.new(
                role: :assistant,
                content: result[:message],
                model_id: model.id,
              )
              # Set custom finish reason before triggering on_end_message
              @context_tracker.finish_reason_override = "finish_agent" if @context_tracker
              # Trigger on_end_message to ensure agent_stop event is emitted
              @on[:end_message]&.call(message)
              return message
            elsif result[:__finish_swarm__]
              # Propagate finish_swarm marker up (don't add to conversation)
              return result
            end
          end

          # Check for halt result
          return result if result.is_a?(RubyLLM::Tool::Halt)

          # Add tool result to conversation
          content = result.is_a?(RubyLLM::Content) ? result : result.to_s
          message = add_message(
            role: :tool,
            content: content,
            tool_call_id: tool_call.id,
          )
          @on[:end_message]&.call(message)

          # Continue loop
          return complete(&block)
        end

        # Multiple tool calls: execute in parallel with rate limiting and hooks
        halt_result = nil

        results = Async do
          tasks = response.tool_calls.map do |_id, tool_call|
            Async do
              # Acquire semaphores (queues if limit reached)
              acquire_semaphores do
                @on[:tool_call]&.call(tool_call)

                # Handle pre_tool_use hook (skip for delegation tools)
                unless delegation_tool_call?(tool_call)
                  pre_result = trigger_pre_tool_use(tool_call)

                  # Handle finish markers first (early exit)
                  # Don't call on_tool_result for finish markers - they're not tool results
                  if pre_result[:finish_agent]
                    result = { __finish_agent__: true, message: pre_result[:custom_result] }
                    next { tool_call: tool_call, result: result, message: nil }
                  end

                  if pre_result[:finish_swarm]
                    result = { __finish_swarm__: true, message: pre_result[:custom_result] }
                    next { tool_call: tool_call, result: result, message: nil }
                  end

                  # Handle blocked execution
                  unless pre_result[:proceed]
                    result = pre_result[:custom_result] || "Tool execution blocked by hook"
                    @on[:tool_result]&.call(result)

                    content = result.is_a?(RubyLLM::Content) ? result : result.to_s
                    message = add_message(
                      role: :tool,
                      content: content,
                      tool_call_id: tool_call.id,
                    )
                    @on[:end_message]&.call(message)

                    next { tool_call: tool_call, result: result, message: message }
                  end
                end

                # Execute tool - Faraday yields during HTTP I/O
                result = execute_tool_with_error_handling(tool_call)

                @on[:tool_result]&.call(result)

                # Trigger post_tool_use hook (skip for delegation tools)
                unless delegation_tool_call?(tool_call)
                  result = trigger_post_tool_use(result, tool_call: tool_call)
                end

                # Check if result is a finish marker (don't add to conversation)
                if result.is_a?(Hash) && (result[:__finish_agent__] || result[:__finish_swarm__])
                  # Finish markers will be detected after parallel execution completes
                  { tool_call: tool_call, result: result, message: nil }
                else
                  # Add tool result to conversation
                  content = result.is_a?(RubyLLM::Content) ? result : result.to_s
                  message = add_message(
                    role: :tool,
                    content: content,
                    tool_call_id: tool_call.id,
                  )
                  @on[:end_message]&.call(message)

                  # Return result data for collection
                  { tool_call: tool_call, result: result, message: message }
                end
              end
            end
          end

          # Wait for all tasks to complete
          tasks.map(&:wait)
        end.wait

        # Check for halt and finish results
        results.each do |data|
          result = data[:result]

          # Check for halt result (from tool execution errors)
          if result.is_a?(RubyLLM::Tool::Halt)
            halt_result = result
            # Continue checking for finish markers below
          end

          # Check for finish markers (from hooks)
          if result.is_a?(Hash)
            if result[:__finish_agent__]
              message = RubyLLM::Message.new(
                role: :assistant,
                content: result[:message],
                model_id: model.id,
              )
              # Set custom finish reason before triggering on_end_message
              @context_tracker.finish_reason_override = "finish_agent" if @context_tracker
              # Trigger on_end_message to ensure agent_stop event is emitted
              @on[:end_message]&.call(message)
              return message
            elsif result[:__finish_swarm__]
              # Propagate finish_swarm marker up
              return result
            end
          end
        end

        # Return halt result if we found one (but no finish markers)
        halt_result = results.find { |data| data[:result].is_a?(RubyLLM::Tool::Halt) }&.dig(:result)

        # Continue automatic loop (recursive call to complete)
        halt_result || complete(&block)
      end

      # Get the provider instance
      #
      # Exposes the RubyLLM provider instance for configuration.
      # This is needed for setting agent_name and other provider-specific settings.
      #
      # @return [RubyLLM::Provider::Base] Provider instance
      attr_reader :provider, :global_semaphore, :local_semaphore, :real_model_info, :context_tracker

      # Get context window limit for the current model
      #
      # Priority order:
      # 1. Explicit context_window parameter (user override)
      # 2. Real model info from RubyLLM registry (searched across all providers)
      # 3. Model info from chat (may be nil if assume_model_exists was used)
      #
      # @return [Integer, nil] Maximum context tokens, or nil if not available
      def context_limit
        # Priority 1: Explicit override
        return @explicit_context_window if @explicit_context_window

        # Priority 2: Real model info from registry (searched across all providers)
        return @real_model_info.context_window if @real_model_info&.context_window

        # Priority 3: Fall back to model from chat
        model.context_window
      rescue StandardError
        nil
      end

      # Calculate cumulative input tokens for the conversation
      #
      # The latest assistant message's input_tokens already includes the cumulative
      # total for the entire conversation (all previous messages, system instructions,
      # tool definitions, etc.). We don't sum across messages as that would double-count.
      #
      # @return [Integer] Total input tokens used in conversation
      def cumulative_input_tokens
        # Find the latest assistant message with input_tokens
        messages.reverse.find { |msg| msg.role == :assistant && msg.input_tokens }&.input_tokens || 0
      end

      # Calculate cumulative output tokens across all assistant messages
      #
      # Unlike input tokens, output tokens are per-response and should be summed.
      #
      # @return [Integer] Total output tokens used in conversation
      def cumulative_output_tokens
        messages.select { |msg| msg.role == :assistant }.sum { |msg| msg.output_tokens || 0 }
      end

      # Calculate total tokens used (input + output)
      #
      # @return [Integer] Total tokens used in conversation
      def cumulative_total_tokens
        cumulative_input_tokens + cumulative_output_tokens
      end

      # Calculate percentage of context window used
      #
      # @return [Float] Percentage (0.0 to 100.0), or 0.0 if limit unavailable
      def context_usage_percentage
        limit = context_limit
        return 0.0 if limit.nil? || limit.zero?

        (cumulative_total_tokens.to_f / limit * 100).round(2)
      end

      # Calculate remaining tokens in context window
      #
      # @return [Integer, nil] Tokens remaining, or nil if limit unavailable
      def tokens_remaining
        limit = context_limit
        return if limit.nil?

        limit - cumulative_total_tokens
      end

      # Compact the conversation history to reduce token usage
      #
      # Uses the Hybrid Production Strategy to intelligently compress the conversation:
      # 1. Tool result pruning - Truncate tool outputs (they're 80%+ of tokens!)
      # 2. Checkpoint creation - LLM-generated summary of conversation chunks
      # 3. Sliding window - Keep recent messages in full detail
      #
      # This is a manual operation - call it when you need to free up context space.
      # The method emits compression events via LogStream for monitoring.
      #
      # ## Usage
      #
      #   # Use defaults
      #   metrics = agent.compact_context
      #   puts metrics.summary
      #
      #   # With custom options
      #   metrics = agent.compact_context(
      #     tool_result_max_length: 300,
      #     checkpoint_threshold: 40,
      #     sliding_window_size: 15
      #   )
      #
      # @param options [Hash] Compression options (see ContextCompactor::DEFAULT_OPTIONS)
      # @return [ContextCompactor::Metrics] Compression statistics
      def compact_context(**options)
        compactor = ContextCompactor.new(self, options)
        compactor.compact
      end

      private

      # Build custom RubyLLM context for base_url/timeout overrides
      #
      # @param provider [String, Symbol] Provider name
      # @param base_url [String, nil] Custom API base URL
      # @param timeout [Integer] Request timeout in seconds
      # @return [RubyLLM::Context] Configured context
      def build_custom_context(provider:, base_url:, timeout:)
        RubyLLM.context do |config|
          # Set timeout for all providers
          config.request_timeout = timeout

          # Configure base_url if specified
          next unless base_url

          case provider.to_s
          when "openai", "deepseek", "perplexity", "mistral", "openrouter"
            config.openai_api_base = base_url
            config.openai_api_key = ENV["OPENAI_API_KEY"] || "dummy-key-for-local"
          when "ollama"
            config.ollama_api_base = base_url
          when "gpustack"
            config.gpustack_api_base = base_url
            config.gpustack_api_key = ENV["GPUSTACK_API_KEY"] || "dummy-key"
          else
            raise ArgumentError,
              "Provider '#{provider}' doesn't support custom base_url. " \
                "Only OpenAI-compatible providers (openai, deepseek, perplexity, mistral, openrouter), " \
                "ollama, and gpustack support custom endpoints."
          end
        end
      end

      # Fetch real model info for accurate context tracking
      #
      # This searches across ALL providers, so it works even when using proxies
      # (e.g., Claude model through OpenAI-compatible proxy).
      #
      # @param model [String] Model ID to lookup
      # @return [void]
      def fetch_real_model_info(model)
        @model_lookup_error = nil
        @real_model_info = begin
          RubyLLM.models.find(model) # Searches all providers when no provider specified
        rescue StandardError => e
          # Store warning info to emit later through LogStream
          suggestions = suggest_similar_models(model)
          @model_lookup_error = {
            model: model,
            error_message: e.message,
            suggestions: suggestions,
          }
          nil
        end
      end

      # Determine which provider to use based on configuration
      #
      # When using base_url with OpenAI-compatible providers and api_version is set to
      # 'v1/responses', use our custom provider that supports the responses API endpoint.
      #
      # @param provider [Symbol, String] The requested provider
      # @param base_url [String, nil] Custom base URL
      # @param api_version [String, nil] API endpoint version
      # @return [Symbol] The provider to use
      def determine_provider(provider, base_url, api_version)
        return provider unless base_url

        # Use custom provider for OpenAI-compatible providers when api_version is v1/responses
        # The custom provider supports both chat/completions and responses endpoints
        case provider.to_s
        when "openai", "deepseek", "perplexity", "mistral", "openrouter"
          if api_version == "v1/responses"
            :openai_with_responses
          else
            provider
          end
        else
          provider
        end
      end

      # Configure the custom provider after creation to use responses API
      #
      # RubyLLM doesn't support passing custom parameters to provider initialization,
      # so we configure the provider after the chat is created.
      def configure_responses_api_provider
        return unless provider.is_a?(SwarmSDK::Providers::OpenAIWithResponses)

        provider.use_responses_api = true
        RubyLLM.logger.debug("SwarmSDK: Configured provider to use responses API")
      end

      # Configure LLM parameters with proper temperature normalization
      #
      # Note: RubyLLM only normalizes temperature (for models that require specific values
      # like gpt-5-mini which requires temperature=1.0) when using with_temperature().
      # The with_params() method is designed for sending unparsed parameters directly to
      # the LLM without provider-specific normalization. Therefore, we extract temperature
      # and call with_temperature() separately to ensure proper normalization.
      #
      # @param params [Hash] Parameter hash (may include temperature and other params)
      # @return [self] Returns self for method chaining
      def configure_parameters(params)
        return self if params.nil? || params.empty?

        # Extract temperature for separate handling
        if params[:temperature]
          with_temperature(params[:temperature])
          params = params.except(:temperature)
        end

        # Apply remaining parameters
        with_params(**params) if params.any?

        self
      end

      # Configure custom HTTP headers for LLM requests
      #
      # @param headers [Hash, nil] Custom HTTP headers
      # @return [self] Returns self for method chaining
      def configure_headers(headers)
        return self if headers.nil? || headers.empty?

        with_headers(**headers)

        self
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

      # Suggest similar models when a model is not found
      #
      # @param query [String] Model name to search for
      # @return [Array<RubyLLM::Model::Info>] Up to 3 similar models
      def suggest_similar_models(query)
        normalized_query = query.to_s.downcase.gsub(/[.\-_]/, "")

        RubyLLM.models.all.select do |model|
          normalized_id = model.id.downcase.gsub(/[.\-_]/, "")
          normalized_id.include?(normalized_query) ||
            model.name&.downcase&.gsub(/[.\-_]/, "")&.include?(normalized_query)
        end.first(3)
      rescue StandardError
        []
      end

      # Execute a tool with ArgumentError handling for missing parameters
      #
      # When a tool is called with missing required parameters, this catches the
      # ArgumentError and returns a helpful message to the LLM with:
      # - Which parameter is missing
      # - Instructions to retry with correct parameters
      # - System reminder showing all required parameters
      #
      # @param tool_call [RubyLLM::ToolCall] Tool call from LLM
      # @return [String, Object] Tool result or error message
      def execute_tool_with_error_handling(tool_call)
        execute_tool(tool_call)
      rescue ArgumentError => e
        # Extract parameter info from the error message
        # ArgumentError messages typically: "missing keyword: parameter_name" or "missing keywords: param1, param2"
        build_missing_parameter_error(tool_call, e)
      end

      # Build a helpful error message for missing tool parameters
      #
      # @param tool_call [RubyLLM::ToolCall] Tool call that failed
      # @param error [ArgumentError] The ArgumentError raised
      # @return [String] Formatted error message with parameter information
      def build_missing_parameter_error(tool_call, error)
        tool_name = tool_call.name
        tool_instance = tools[tool_name.to_sym]

        # Extract which parameters are missing from error message
        missing_params = if error.message.match(/missing keyword(?:s)?: (.+)/)
          ::Regexp.last_match(1).split(", ").map(&:strip)
        else
          ["unknown"]
        end

        # Get tool parameter information from RubyLLM::Tool
        param_info = if tool_instance.respond_to?(:parameters)
          # RubyLLM tools have a parameters method that returns { name => Parameter }
          tool_instance.parameters.map do |_param_name, param_obj|
            {
              name: param_obj.name.to_s,
              type: param_obj.type,
              description: param_obj.description,
              required: param_obj.required,
            }
          end
        else
          []
        end

        # Build error message
        error_message = "Error calling #{tool_name}: #{error.message}\n\n"
        error_message += "Please retry the tool call with all required parameters.\n\n"

        # Add system reminder with parameter information
        if param_info.any?
          required_params = param_info.select { |p| p[:required] }

          error_message += "<system-reminder>\n"
          error_message += "The #{tool_name} tool requires the following parameters:\n\n"

          required_params.each do |param|
            error_message += "- #{param[:name]} (#{param[:type]}, REQUIRED): #{param[:description]}\n"
          end

          optional_params = param_info.reject { |p| p[:required] }
          if optional_params.any?
            error_message += "\nOptional parameters:\n"
            optional_params.each do |param|
              error_message += "- #{param[:name]} (#{param[:type]}): #{param[:description]}\n"
            end
          end

          error_message += "\nYou were missing: #{missing_params.join(", ")}\n"
          error_message += "</system-reminder>"
        else
          error_message += "Missing parameters: #{missing_params.join(", ")}"
        end

        error_message
      end
    end
  end
end
