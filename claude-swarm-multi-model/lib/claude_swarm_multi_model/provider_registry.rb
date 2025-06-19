# frozen_string_literal: true

module ClaudeSwarmMultiModel
  # Registry for managing different LLM providers
  module ProviderRegistry
    PROVIDERS = {
      "openai" => {
        name: "OpenAI",
        models: %w[gpt-4o gpt-4o-mini gpt-4-turbo gpt-4 gpt-3.5-turbo],
        env_var: "OPENAI_API_KEY"
      },
      "gemini" => {
        name: "Google Gemini",
        models: %w[gemini-pro gemini-1.5-pro gemini-1.5-flash],
        env_var: "GEMINI_API_KEY"
      },
      "groq" => {
        name: "Groq",
        models: %w[llama-3.3-70b-versatile llama-3.2-90b-text-preview mixtral-8x7b-32768],
        env_var: "GROQ_API_KEY"
      },
      "deepseek" => {
        name: "DeepSeek",
        models: %w[deepseek-chat deepseek-coder],
        env_var: "DEEPSEEK_API_KEY"
      },
      "together" => {
        name: "Together AI",
        models: %w[
          meta-llama/Meta-Llama-3.1-405B-Instruct-Turbo
          meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo
          meta-llama/Llama-3.2-90B-Vision-Instruct-Turbo
          mistralai/Mixtral-8x22B-Instruct-v0.1
          Qwen/Qwen2.5-72B-Instruct-Turbo
          google/gemma-2-27b-it
        ],
        env_var: "TOGETHER_API_KEY"
      },
      "local" => {
        name: "Local LLM",
        models: ["*"], # Accept any model
        env_var: "LOCAL_LLM_BASE_URL"
      }
    }.freeze

    class << self
      def list_providers
        PROVIDERS.transform_values { |config| { name: config[:name], models: config[:models] } }
      end

      def supported_provider?(provider)
        PROVIDERS.key?(provider)
      end

      def supported_model?(provider, model)
        return false unless supported_provider?(provider)
        return true if provider == "local" # Local accepts any model
        PROVIDERS[provider][:models].include?(model)
      end

      def get_provider_config(provider)
        PROVIDERS[provider]
      end

      def detect_available_providers
        available = []
        PROVIDERS.each do |key, config|
          if key == "local" || (config[:env_var] && ENV[config[:env_var]])
            available << key
          end
        end
        available
      end

      def provider_available?(provider)
        return false unless supported_provider?(provider)
        return true if provider == "local"
        env_var = PROVIDERS[provider][:env_var]
        env_var && ENV[env_var]
      end

      def get_env_var_for_provider(provider)
        return nil unless supported_provider?(provider)
        PROVIDERS[provider][:env_var]
      end
    end
  end
end
