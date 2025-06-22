# frozen_string_literal: true

require "securerandom"

module ClaudeSwarm
  module Providers
    # Executor for non-Anthropic LLM providers using ruby_llm gem
    class LlmExecutor < BaseExecutor
      def initialize(provider:, model:, api_key_env: nil, api_base_env: nil,
                     assume_model_exists: false, mcp_config: nil, vibe: false,
                     additional_directories: [], **common_options)
        super(**common_options)

        @provider = provider.to_s.downcase
        @model = model
        @assume_model_exists = assume_model_exists
        @mcp_config = mcp_config
        @vibe = vibe
        @additional_directories = additional_directories

        # Check if ruby_llm is available
        require_ruby_llm!

        # Create LLM context with provider configuration
        setup_llm_context(api_key_env, api_base_env)
      end

      def execute(prompt, options = {})
        start_time = Time.now

        # Log the request
        log_request(prompt)

        # Build messages array
        messages = build_messages(prompt, options)

        # Check if provider supports tools and prepare them
        tools = prepare_tools(options) if provider_supports_tools?

        # Execute the LLM request with streaming support
        response = execute_llm_request(messages, tools)

        # Calculate duration
        duration_ms = ((Time.now - start_time) * 1000).round

        # Normalize and log response
        result = ResponseNormalizer.normalize(
          provider: @provider,
          response: response,
          duration_ms: duration_ms,
          session_id: session_id
        )

        # Update session state
        @last_response = result
        @session_id ||= result["session_id"]

        # Log the response
        log_response(result)

        result
      rescue StandardError => e
        handle_error(e)
      end

      private

      def require_ruby_llm!
        return if defined?(::RubyLlm)

        begin
          require "ruby_llm"
        rescue LoadError
          raise Error, <<~MSG
            The ruby_llm gem is not available.

            To use #{@provider} models, install the claude-swarm-providers gem:

              gem install claude-swarm-providers

            Or add to your Gemfile:

              gem 'claude-swarm-providers'

            Then restart your application.
          MSG
        end
      end

      def setup_llm_context(api_key_env, api_base_env)
        # Create a context for this instance to avoid polluting global config
        @llm_context = RubyLlm.context do |config|
          # Get API key from environment
          key_env = api_key_env || default_api_key_env
          api_key = ENV.fetch(key_env, nil)
          raise Error, "Missing API key in environment variable: #{key_env}" unless api_key

          # Configure provider
          case @provider
          when "openai"
            config.openai_api_key = api_key
            setup_openai_base_url(config, api_base_env)
          when "google", "gemini"
            config.gemini_api_key = api_key
          when "cohere"
            config.cohere_api_key = api_key
          else
            raise Error, "Unsupported provider: #{@provider}"
          end
        end
      end

      def setup_openai_base_url(config, api_base_env)
        return unless Capabilities.supports?(@provider, :supports_custom_base)

        # Check for custom base URL
        if api_base_env && ENV[api_base_env]
          config.openai_api_base = ENV[api_base_env]
        elsif ENV["OPENAI_API_BASE"]
          config.openai_api_base = ENV["OPENAI_API_BASE"]
        end
      end

      def default_api_key_env
        case @provider
        when "openai" then "OPENAI_API_KEY"
        when "google", "gemini" then "GOOGLE_API_KEY"
        when "cohere" then "COHERE_API_KEY"
        else "#{@provider.upcase}_API_KEY"
        end
      end

      def build_messages(prompt, options)
        messages = []

        # Add system prompt if provided
        if options[:system_prompt] && Capabilities.supports?(@provider, :supports_system_prompt)
          messages << { role: "system", content: options[:system_prompt] }
        end

        # Add user prompt
        messages << { role: "user", content: prompt }

        messages
      end

      def provider_supports_tools?
        Capabilities.supports?(@provider, :supports_tools)
      end

      def prepare_tools(options)
        return nil unless options[:allowed_tools]

        # Filter allowed tools
        allowed = Array(options[:allowed_tools])
        disallowed = Array(options[:disallowed_tools])
        tools = allowed - disallowed

        # Handle MCP connections
        options[:connections]&.each do |connection|
          tools << "mcp__#{connection}"
        end

        # Map tools to provider format
        map_tools_for_provider(tools)
      end

      def map_tools_for_provider(tools)
        # TODO: Implement actual tool mapping based on provider's tool format
        # For now, return tools as-is for providers that support JSON format
        # For now, return tools as-is regardless of format
        # Future: implement format conversion based on provider needs
        tools
      end

      def execute_llm_request(messages, tools)
        # Prepare request parameters
        params = {
          messages: messages,
          model: @model,
          provider: @provider.to_sym
        }

        # Add tools if available
        params[:tools] = tools if tools

        # Add assume_model_exists flag
        params[:assume_model_exists] = @assume_model_exists if @assume_model_exists

        # Execute with streaming if supported
        if Capabilities.supports?(@provider, :supports_streaming)
          execute_with_streaming(params)
        else
          @llm_context.chat(**params)
        end
      end

      def execute_with_streaming(params)
        chunks = []
        response = nil

        @llm_context.chat(**params) do |chunk|
          chunks << chunk
          log_streaming_chunk(chunk)

          # Capture the final response
          response = chunk if chunk.respond_to?(:content) || chunk.respond_to?(:message)
        end

        # Return the accumulated response
        response || build_response_from_chunks(chunks)
      end

      def build_response_from_chunks(chunks)
        # Build a complete response from streaming chunks
        content = chunks.map { |c| extract_chunk_content(c) }.join

        # Create a response-like object
        Struct.new(:content, :input_tokens, :output_tokens).new(
          content,
          chunks.first&.input_tokens || 0,
          chunks.last&.output_tokens || 0
        )
      end

      def extract_chunk_content(chunk)
        if chunk.respond_to?(:content)
          chunk.content
        elsif chunk.respond_to?(:text)
          chunk.text
        elsif chunk.is_a?(Hash)
          chunk["content"] || chunk["text"] || ""
        else
          chunk.to_s
        end
      end

      def log_request(prompt)
        caller_info = format_caller_info
        instance_info = format_instance_info

        @logger.info("#{caller_info} -> #{instance_info}: \n---\n#{prompt}\n---")

        # Log to JSON
        event = {
          type: "request",
          from_instance: @calling_instance,
          from_instance_id: @calling_instance_id,
          to_instance: @instance_name,
          to_instance_id: @instance_id,
          prompt: prompt,
          model: @model,
          provider: @provider,
          timestamp: Time.now.iso8601
        }

        append_to_session_json(event)
      end

      def log_response(response)
        caller_info = format_caller_info
        instance_info = format_instance_info

        cost_str = format_cost(response["total_cost"])
        duration_str = "#{response["duration_ms"]}ms"

        @logger.info(
          "(#{cost_str} - #{duration_str}) #{instance_info} -> #{caller_info}: \n---\n#{response["result"]}\n---"
        )
      end

      def log_streaming_chunk(chunk)
        return unless chunk

        event = {
          type: "chunk",
          content: extract_chunk_content(chunk),
          timestamp: Time.now.iso8601
        }

        append_to_session_json(event)
      end

      def format_caller_info
        info = @calling_instance || "unknown"
        info += " (#{@calling_instance_id})" if @calling_instance_id
        info
      end

      def format_instance_info
        info = @instance_name || @provider
        info += " (#{@instance_id})" if @instance_id
        info
      end

      def format_cost(cost)
        format("$%.5f", cost)
      end

      def generate_session_id
        "llm-#{@provider}-#{Time.now.strftime("%Y%m%d%H%M%S")}-#{SecureRandom.hex(4)}"
      end

      def session_id
        @session_id ||= generate_session_id
      end

      def handle_error(error)
        # Check error class name since we might not have the actual classes loaded
        case error.class.name
        when "RubyLlm::AuthenticationError"
          raise Error, "Authentication failed. Check your #{default_api_key_env} environment variable."
        when "RubyLlm::ModelNotFoundError"
          raise Error, "Model '#{@model}' not found for #{@provider}. Set assume_model_exists: true for custom models."
        when "RubyLlm::RateLimitError"
          raise Error, "Rate limit exceeded for #{@provider}. Please wait and try again."
        when "RubyLlm::NetworkError"
          raise Error, "Network error connecting to #{@provider}. Check your internet connection."
        else
          @logger.error("LLM execution error: #{error.class} - #{error.message}")
          @logger.error(error.backtrace.join("\n")) if error.respond_to?(:backtrace)
          raise error
        end
      end
    end
  end
end
