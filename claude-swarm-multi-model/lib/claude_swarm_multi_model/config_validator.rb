# frozen_string_literal: true

module ClaudeSwarmMultiModel
  module ConfigValidator
    # Supported providers and their requirements
    PROVIDERS = {
      "anthropic" => {
        models: %w[claude-3-5-sonnet-20241022 claude-3-5-haiku-20241022 claude-3-opus-20240229 claude-3-sonnet-20240229 claude-3-haiku-20240307],
        api_key_env: "ANTHROPIC_API_KEY",
        required: false # Claude Swarm handles this natively
      },
      "openai" => {
        models: %w[gpt-4o gpt-4o-mini gpt-4-turbo gpt-4 gpt-3.5-turbo o1-preview o1-mini],
        api_key_env: "OPENAI_API_KEY",
        required: true
      },
      "gemini" => {
        models: %w[gemini-2.0-flash-exp gemini-1.5-pro gemini-1.5-flash gemini-1.0-pro],
        api_key_env: "GEMINI_API_KEY",
        required: true
      },
      "groq" => {
        models: %w[llama-3.3-70b-versatile llama-3.1-8b-instant mixtral-8x7b-32768 gemma2-9b-it],
        api_key_env: "GROQ_API_KEY",
        required: true
      },
      "deepseek" => {
        models: %w[deepseek-chat deepseek-coder],
        api_key_env: "DEEPSEEK_API_KEY",
        required: true
      },
      "together" => {
        models: %w[meta-llama/Llama-3.2-90B-Vision-Instruct-Turbo meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo],
        api_key_env: "TOGETHER_API_KEY",
        required: true
      },
      "local" => {
        models: :any, # Any model name is valid for local providers
        api_key_env: nil,
        required: false,
        base_url_env: "LOCAL_LLM_BASE_URL"
      }
    }.freeze

    class << self
      # Process the entire configuration after it's parsed
      def process_config(config)
        # Validate that at least one instance uses a non-Anthropic provider
        instances = config.instance_names.map { |name| config.instances[name] }

        providers_in_use = instances.map { |inst| inst[:provider] || "anthropic" }.uniq
        non_anthropic_providers = providers_in_use - ["anthropic"]

        return unless non_anthropic_providers.any?

        # Validate API keys for required providers first
        non_anthropic_providers.each do |provider|
          validate_provider_requirements(provider)
        end

        # Then check that ruby_llm is available
        begin
          require "ruby_llm"
        rescue LoadError
          raise ClaudeSwarm::Error, "The ruby_llm gem is required for multi-model support. Please install it with: gem install ruby_llm"
        end
      end

      # Validate an individual instance configuration
      def validate_instance(instance_name, instance_config)
        provider = instance_config["provider"] || "anthropic"
        model = instance_config["model"]

        # Skip validation for default Anthropic provider
        return if provider == "anthropic" && !instance_config.key?("provider")

        # Validate provider is supported
        unless PROVIDERS.key?(provider)
          supported = PROVIDERS.keys.join(", ")
          raise ClaudeSwarm::Error, "Instance '#{instance_name}' uses unsupported provider '#{provider}'. Supported providers: #{supported}"
        end

        provider_info = PROVIDERS[provider]

        # Validate model if provider has a specific list
        if provider_info[:models].is_a?(Array) && model && !provider_info[:models].include?(model)
          supported_models = provider_info[:models].join(", ")
          raise ClaudeSwarm::Error,
                "Instance '#{instance_name}' uses unsupported model '#{model}' for provider '#{provider}'. " \
                "Supported models: #{supported_models}"
        end

        # Warn if model is not specified for non-Anthropic providers
        if provider != "anthropic" && !model
          puts "Warning: Instance '#{instance_name}' with provider '#{provider}' does not specify a model. A default will be used."
        end

        # Store provider info in instance config for later use
        instance_config["api_key_env"] = provider_info[:api_key_env] if provider_info[:api_key_env]
        instance_config["base_url_env"] = provider_info[:base_url_env] if provider_info[:base_url_env]
      end

      private

      def validate_provider_requirements(provider)
        provider_info = PROVIDERS[provider]
        return unless provider_info[:required]

        api_key_env = provider_info[:api_key_env]
        raise ClaudeSwarm::Error, "Provider '#{provider}' requires environment variable #{api_key_env} to be set" if api_key_env && !ENV[api_key_env]

        base_url_env = provider_info[:base_url_env]
        return unless base_url_env && provider == "local" && !ENV[base_url_env]

        raise ClaudeSwarm::Error,
              "Local provider requires environment variable #{base_url_env} to be set with the base URL of your local LLM server"
      end
    end
  end
end
