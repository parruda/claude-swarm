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
      # @param agent_name [Symbol, nil] Agent identifier (for plugin callbacks)
      # @param global_semaphore [Async::Semaphore, nil] Shared across all agents (not part of definition)
      # @param options [Hash] Additional options to pass to RubyLLM::Chat
      # @raise [ArgumentError] If provider doesn't support custom base_url or provider not specified with base_url
      def initialize(definition:, agent_name: nil, global_semaphore: nil, **options)
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

        # Agent identifier (for plugin callbacks)
        @agent_name = agent_name

        # Context manager for ephemeral messages and future context optimization
        @context_manager = ContextManager.new

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

        # Track which tools are immutable (cannot be removed by dynamic tool swapping)
        # Default: Think, Clock, and TodoWrite are immutable utilities
        # Plugins can mark additional tools as immutable via on_agent_initialized hook
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

      # Mark tools as immutable (cannot be removed by dynamic tool swapping)
      #
      # Called by plugins during on_agent_initialized lifecycle hook to mark
      # their tools as immutable. This allows plugins to protect their core
      # tools from being removed by dynamic tool swapping operations.
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
        is_first = SystemReminderInjector.first_message?(self)

        if is_first
          # Collect plugin reminders first
          plugin_reminders = collect_plugin_reminders(prompt, is_first_message: true)

          # Build full prompt with embedded plugin reminders
          full_prompt = prompt
          plugin_reminders.each do |reminder|
            full_prompt = "#{full_prompt}\n\n#{reminder}"
          end

          # Inject first message reminders (includes system reminders + toolset + after)
          # SystemReminderInjector will embed all reminders in the prompt via add_message
          SystemReminderInjector.inject_first_message_reminders(self, full_prompt)

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
          # Build prompt with embedded reminders (if needed)
          full_prompt = prompt

          # Add periodic TodoWrite reminder if needed
          if SystemReminderInjector.should_inject_todowrite_reminder?(self, @last_todowrite_message_index)
            full_prompt = "#{full_prompt}\n\n#{SystemReminderInjector::TODOWRITE_PERIODIC_REMINDER}"
            # Update tracking
            @last_todowrite_message_index = SystemReminderInjector.find_last_todowrite_index(self)
          end

          # Collect plugin reminders and embed them
          plugin_reminders = collect_plugin_reminders(full_prompt, is_first_message: false)
          plugin_reminders.each do |reminder|
            full_prompt = "#{full_prompt}\n\n#{reminder}"
          end

          # Normal ask behavior for subsequent messages
          # This calls super which goes to HookIntegration's ask override
          # HookIntegration will call add_message, and we'll extract reminders there
          super(full_prompt, **options)
        end
      end

      # Override add_message to automatically extract and strip system reminders
      #
      # System reminders are extracted and tracked as ephemeral content (embedded
      # when sent to LLM but not persisted in conversation history).
      #
      # @param message_or_attributes [RubyLLM::Message, Hash] Message object or attributes hash
      # @return [RubyLLM::Message] The added message (with clean content)
      def add_message(message_or_attributes)
        # Handle both forms: add_message(message) and add_message({role: :user, content: "text"})
        if message_or_attributes.is_a?(RubyLLM::Message)
          # Message object provided
          msg = message_or_attributes
          content_str = msg.content.is_a?(RubyLLM::Content) ? msg.content.text : msg.content.to_s

          # Extract system reminders
          if @context_manager.has_system_reminders?(content_str)
            reminders = @context_manager.extract_system_reminders(content_str)
            clean_content_str = @context_manager.strip_system_reminders(content_str)

            clean_content = if msg.content.is_a?(RubyLLM::Content)
              RubyLLM::Content.new(clean_content_str, msg.content.attachments)
            else
              clean_content_str
            end

            clean_message = RubyLLM::Message.new(
              role: msg.role,
              content: clean_content,
              tool_call_id: msg.tool_call_id,
            )

            result = super(clean_message)

            # Track reminders as ephemeral
            reminders.each do |reminder|
              @context_manager.add_ephemeral_reminder(reminder, messages_array: @messages)
            end

            result
          else
            # No reminders - call parent normally
            super(msg)
          end
        else
          # Hash attributes provided
          attrs = message_or_attributes
          content_value = attrs[:content] || attrs["content"]
          content_str = content_value.is_a?(RubyLLM::Content) ? content_value.text : content_value.to_s

          # Extract system reminders
          if @context_manager.has_system_reminders?(content_str)
            reminders = @context_manager.extract_system_reminders(content_str)
            clean_content_str = @context_manager.strip_system_reminders(content_str)

            clean_content = if content_value.is_a?(RubyLLM::Content)
              RubyLLM::Content.new(clean_content_str, content_value.attachments)
            else
              clean_content_str
            end

            clean_attrs = attrs.merge(content: clean_content)
            result = super(clean_attrs)

            # Track reminders as ephemeral
            reminders.each do |reminder|
              @context_manager.add_ephemeral_reminder(reminder, messages_array: @messages)
            end

            result
          else
            # No reminders - call parent normally
            super(attrs)
          end
        end
      end

      # Collect reminders from all plugins
      #
      # Plugins can contribute system reminders based on the user's message.
      # Returns array of reminder strings to be embedded in the user prompt.
      #
      # @param prompt [String] User's message
      # @param is_first_message [Boolean] True if first message
      # @return [Array<String>] Array of reminder strings
      def collect_plugin_reminders(prompt, is_first_message:)
        return [] unless @agent_name # Skip if agent_name not set

        # Collect reminders from all plugins
        PluginRegistry.all.flat_map do |plugin|
          plugin.on_user_message(
            agent_name: @agent_name,
            prompt: prompt,
            is_first_message: is_first_message,
          )
        end.compact
      end

      # Override complete() to inject ephemeral messages
      #
      # Ephemeral messages are sent to the LLM for the current turn only
      # and are NOT stored in the conversation history. This prevents
      # system reminders from accumulating and being resent every turn.
      #
      # @param options [Hash] Options to pass to provider
      # @return [RubyLLM::Message] LLM response
      def complete(**options, &block)
        # Prepare messages: persistent + ephemeral for this turn
        messages_for_llm = @context_manager.prepare_for_llm(@messages)

        # Call provider with retry logic for transient failures
        response = call_llm_with_retry do
          @provider.complete(
            messages_for_llm,
            tools: @tools,
            temperature: @temperature,
            model: @model,
            params: @params,
            headers: @headers,
            schema: @schema,
            &wrap_streaming_block(&block)
          )
        end

        # Handle nil response from provider (malformed API response)
        if response.nil?
          raise RubyLLM::Error, "Provider returned nil response. This usually indicates a malformed API response " \
            "that couldn't be parsed.\n\n" \
            "Provider: #{@provider.class.name}\n" \
            "API Base: #{@provider.api_base}\n" \
            "Model: #{@model.id}\n" \
            "Response: #{response.inspect}\n\n" \
            "The API endpoint returned a response that couldn't be parsed into a valid Message object. " \
            "Enable RubyLLM debug logging (RubyLLM.logger.level = Logger::DEBUG) to see the raw API response."
        end

        @on[:new_message]&.call unless block

        # Handle schema parsing if needed
        if @schema && response.content.is_a?(String)
          begin
            response.content = JSON.parse(response.content)
          rescue JSON::ParserError
            # Keep as string if parsing fails
          end
        end

        # Add response to persistent history
        add_message(response)
        @on[:end_message]&.call(response)

        # Clear ephemeral messages after use
        @context_manager.clear_ephemeral

        # Handle tool calls if present
        if response.tool_call?
          handle_tool_calls(response, &block)
        else
          response
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
          # add_message automatically extracts reminders and stores them as ephemeral
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

                    # add_message automatically extracts reminders
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
                  # add_message automatically extracts reminders and stores them as ephemeral
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
      attr_reader :provider, :global_semaphore, :local_semaphore, :real_model_info, :context_tracker, :context_manager

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

      # Call LLM with retry logic for transient failures
      #
      # Retries up to 10 times with fixed 10-second delays for:
      # - Network errors
      # - Proxy failures
      # - Transient API errors
      #
      # @yield Block that makes the LLM call
      # @return [RubyLLM::Message] LLM response
      # @raise [StandardError] If all retries exhausted
      def call_llm_with_retry(max_retries: 10, delay: 10, &block)
        attempts = 0

        loop do
          attempts += 1

          begin
            return yield
          rescue StandardError => e
            # Check if we should retry
            if attempts >= max_retries
              # Emit final failure log
              LogStream.emit(
                type: "llm_retry_exhausted",
                agent: @agent_name,
                model: @model&.id,
                attempts: attempts,
                error_class: e.class.name,
                error_message: e.message,
              )
              raise
            end

            # Emit retry attempt log
            LogStream.emit(
              type: "llm_retry_attempt",
              agent: @agent_name,
              model: @model&.id,
              attempt: attempts,
              max_retries: max_retries,
              error_class: e.class.name,
              error_message: e.message,
              retry_delay: delay,
            )

            # Wait before retry
            sleep(delay)
          end
        end
      end

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
            # Use standard 'system' role instead of 'developer' for OpenAI-compatible proxies
            # Most proxies don't support OpenAI's newer 'developer' role convention
            config.openai_use_system_role = true
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

      # Execute a tool with error handling for common issues
      #
      # Handles:
      # - Missing required parameters (validated before calling)
      # - Tool doesn't exist (nil.call)
      # - Other ArgumentErrors (from tool execution)
      #
      # Returns helpful messages with system reminders showing available tools
      # or required parameters.
      #
      # @param tool_call [RubyLLM::ToolCall] Tool call from LLM
      # @return [String, Object] Tool result or error message
      def execute_tool_with_error_handling(tool_call)
        tool_name = tool_call.name
        tool_instance = tools[tool_name.to_sym]

        # Check if tool exists
        unless tool_instance
          return build_tool_not_found_error(tool_call)
        end

        # Validate required parameters BEFORE calling the tool
        validation_error = validate_tool_parameters(tool_call, tool_instance)
        return validation_error if validation_error

        # Execute the tool
        execute_tool(tool_call)
      rescue ArgumentError => e
        # This is an ArgumentError from INSIDE the tool execution (not missing params)
        # Still try to provide helpful error message
        build_argument_error(tool_call, e)
      end

      # Validate that all required tool parameters are present
      #
      # @param tool_call [RubyLLM::ToolCall] Tool call from LLM
      # @param tool_instance [RubyLLM::Tool] Tool instance
      # @return [String, nil] Error message if validation fails, nil if valid
      def validate_tool_parameters(tool_call, tool_instance)
        return unless tool_instance.respond_to?(:parameters)

        # Get required parameters from tool definition
        required_params = tool_instance.parameters.select { |_, param| param.required }

        # Check which required parameters are missing from the tool call
        # ToolCall stores arguments in tool_call.arguments (not .parameters)
        missing_params = required_params.reject do |param_name, _param|
          tool_call.arguments.key?(param_name.to_s) || tool_call.arguments.key?(param_name.to_sym)
        end

        return if missing_params.empty?

        # Build missing parameter error
        build_missing_parameters_error(tool_call, tool_instance, missing_params.keys)
      end

      # Build error message for missing required parameters
      #
      # @param tool_call [RubyLLM::ToolCall] Tool call that failed
      # @param tool_instance [RubyLLM::Tool] Tool instance
      # @param missing_param_names [Array<Symbol>] Names of missing parameters
      # @return [String] Formatted error message
      def build_missing_parameters_error(tool_call, tool_instance, missing_param_names)
        tool_name = tool_call.name

        # Get all parameter information
        param_info = tool_instance.parameters.map do |_param_name, param_obj|
          {
            name: param_obj.name.to_s,
            type: param_obj.type,
            description: param_obj.description,
            required: param_obj.required,
          }
        end

        # Format missing parameter names nicely
        missing_list = missing_param_names.map(&:to_s).join(", ")

        error_message = "Error calling #{tool_name}: missing parameters: #{missing_list}\n\n"
        error_message += build_parameter_reminder(tool_name, param_info)
        error_message
      end

      # Build a helpful error message for ArgumentErrors from tool execution
      #
      # This handles ArgumentErrors that come from INSIDE the tool (not our validation).
      # We still try to be helpful if it looks like a parameter issue.
      #
      # @param tool_call [RubyLLM::ToolCall] Tool call that failed
      # @param error [ArgumentError] The ArgumentError raised
      # @return [String] Formatted error message
      def build_argument_error(tool_call, error)
        tool_name = tool_call.name

        # Just report the error - we already validated parameters, so this is an internal tool error
        "Error calling #{tool_name}: #{error.message}"
      end

      # Build system reminder with parameter information
      #
      # @param tool_name [String] Tool name
      # @param param_info [Array<Hash>] Parameter information
      # @return [String] Formatted parameter reminder
      def build_parameter_reminder(tool_name, param_info)
        return "" if param_info.empty?

        required_params = param_info.select { |p| p[:required] }
        optional_params = param_info.reject { |p| p[:required] }

        reminder = "<system-reminder>\n"
        reminder += "CRITICAL: The #{tool_name} tool call failed due to missing parameters.\n\n"
        reminder += "ALL REQUIRED PARAMETERS for #{tool_name}:\n\n"

        required_params.each do |param|
          reminder += "- #{param[:name]} (#{param[:type]}): #{param[:description]}\n"
        end

        if optional_params.any?
          reminder += "\nOptional parameters:\n"
          optional_params.each do |param|
            reminder += "- #{param[:name]} (#{param[:type]}): #{param[:description]}\n"
          end
        end

        reminder += "\nINSTRUCTIONS FOR RECOVERY:\n"
        reminder += "1. Use the Think tool to reason about what value EACH required parameter should have\n"
        reminder += "2. After thinking, retry the #{tool_name} tool call with ALL required parameters included\n"
        reminder += "3. Do NOT skip any required parameters - the tool will fail again if you do\n"
        reminder += "</system-reminder>"

        reminder
      end

      # Build a helpful error message when a tool doesn't exist
      #
      # @param tool_call [RubyLLM::ToolCall] Tool call that failed
      # @return [String] Formatted error message with available tools list
      def build_tool_not_found_error(tool_call)
        tool_name = tool_call.name
        available_tools = tools.keys.map(&:to_s).sort

        error_message = "Error: Tool '#{tool_name}' is not available.\n\n"
        error_message += "You attempted to use '#{tool_name}', but this tool is not in your current toolset.\n\n"

        error_message += "<system-reminder>\n"
        error_message += "Your available tools are:\n"
        available_tools.each do |name|
          error_message += "  - #{name}\n"
        end
        error_message += "\nDo NOT attempt to use tools that are not in this list.\n"
        error_message += "</system-reminder>"

        error_message
      end
    end
  end
end
