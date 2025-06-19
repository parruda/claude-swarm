# frozen_string_literal: true

require "ruby_llm"
require_relative "../providers/registry"

module ClaudeSwarmMultiModel
  module MCP
    # Executes LLM requests through different providers
    class Executor
      def initialize(config = {})
        @config = config
        @provider = validate_provider(config[:provider] || "openai")
        @model = config[:model] || Providers::Registry.default_model(@provider)
        @api_key = config[:api_key] || ENV.fetch(Providers::Registry.env_key(@provider), nil)

        validate_config!
        @client = setup_client
      end

      # Execute a request to the LLM
      def execute(prompt, options = {})
        messages = build_messages(prompt, options[:system_prompt])

        response = if options[:stream]
                     stream_response(messages, options)
                   else
                     complete_response(messages, options)
                   end

        format_response(response)
      end

      private

      def validate_provider(provider)
        normalized = provider.to_s.downcase
        unless Providers::Registry.supported?(normalized)
          supported = Providers::Registry.list_providers.join(", ")
          raise ArgumentError, "Unsupported provider: #{provider}. Supported: #{supported}"
        end
        normalized
      end

      def validate_config!
        raise ArgumentError, "API key required. Set #{Providers::Registry.env_key(@provider)} or provide api_key" unless @api_key

        return unless @model && !Providers::Registry.validate_model(@provider, @model)

        available = Providers::Registry.list_models(@provider).join(", ")
        raise ArgumentError, "Invalid model '#{@model}' for #{@provider}. Available: #{available}"
      end

      def setup_client
        case @provider.downcase
        when "openai"
          RubyLlm::Providers::OpenAI.new(api_key: @api_key)
        when "anthropic"
          RubyLlm::Providers::Anthropic.new(api_key: @api_key)
        when "google", "gemini"
          RubyLlm::Providers::Google.new(api_key: @api_key)
        when "cohere"
          RubyLlm::Providers::Cohere.new(api_key: @api_key)
        else
          raise "Unsupported provider: #{@provider}"
        end
      end

      def build_messages(prompt, system_prompt = nil)
        messages = []

        if system_prompt
          messages << { role: "system", content: system_prompt }
        elsif @config[:system_prompt]
          messages << { role: "system", content: @config[:system_prompt] }
        end

        messages << { role: "user", content: prompt }
        messages
      end

      def complete_response(messages, options)
        @client.chat(
          model: options[:model] || @model,
          messages: messages,
          temperature: options[:temperature] || @config[:temperature] || 0.7,
          max_tokens: options[:max_tokens] || @config[:max_tokens] || 4096
        )
      end

      def stream_response(messages, options)
        chunks = []

        @client.stream_chat(
          model: options[:model] || @model,
          messages: messages,
          temperature: options[:temperature] || @config[:temperature] || 0.7,
          max_tokens: options[:max_tokens] || @config[:max_tokens] || 4096
        ) do |chunk|
          chunks << chunk
          # Could yield chunk here for real-time streaming
        end

        # Combine chunks into final response
        {
          content: chunks.map { |c| c[:content] }.join,
          usage: chunks.last[:usage] || calculate_usage(chunks)
        }
      end

      def format_response(response)
        {
          content: response[:content] || response.dig(:choices, 0, :message, :content),
          model: response[:model] || @model,
          usage: response[:usage] || {
            prompt_tokens: 0,
            completion_tokens: 0,
            total_tokens: 0
          }
        }
      end

      def calculate_usage(chunks)
        # Estimate token usage from chunks if not provided
        content = chunks.map { |c| c[:content] }.join
        tokens = content.split.size * 1.3 # Rough estimate

        {
          prompt_tokens: 0,
          completion_tokens: tokens.to_i,
          total_tokens: tokens.to_i
        }
      end
    end
  end
end
