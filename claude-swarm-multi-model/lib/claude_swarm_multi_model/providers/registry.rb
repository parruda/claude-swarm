# frozen_string_literal: true

module ClaudeSwarmMultiModel
  module Providers
    # Registry of supported LLM providers and their configurations
    class Registry
      PROVIDERS = {
        "openai" => {
          name: "OpenAI",
          models: %w[gpt-4o gpt-4o-mini gpt-4-turbo gpt-4 gpt-3.5-turbo],
          default_model: "gpt-4o",
          env_key: "OPENAI_API_KEY",
          supports_streaming: true
        },
        "anthropic" => {
          name: "Anthropic",
          models: %w[claude-3-5-sonnet-20241022 claude-3-opus-20240229 claude-3-sonnet-20240229 claude-3-haiku-20240307],
          default_model: "claude-3-5-sonnet-20241022",
          env_key: "ANTHROPIC_API_KEY",
          supports_streaming: true
        },
        "google" => {
          name: "Google",
          models: %w[gemini-1.5-pro gemini-1.5-flash gemini-pro],
          default_model: "gemini-1.5-pro",
          env_key: "GOOGLE_API_KEY",
          supports_streaming: true
        },
        "gemini" => {
          # Alias for google
          name: "Google Gemini",
          models: %w[gemini-1.5-pro gemini-1.5-flash gemini-pro],
          default_model: "gemini-1.5-pro",
          env_key: "GOOGLE_API_KEY",
          supports_streaming: true
        },
        "cohere" => {
          name: "Cohere",
          models: %w[command-r-plus command-r command],
          default_model: "command-r-plus",
          env_key: "COHERE_API_KEY",
          supports_streaming: true
        }
      }.freeze

      class << self
        def supported?(provider)
          PROVIDERS.key?(provider.to_s.downcase)
        end

        def get(provider)
          PROVIDERS[provider.to_s.downcase]
        end

        def default_model(provider)
          config = get(provider)
          config ? config[:default_model] : nil
        end

        def env_key(provider)
          config = get(provider)
          config ? config[:env_key] : "#{provider.upcase}_API_KEY"
        end

        def validate_model(provider, model)
          config = get(provider)
          return false unless config

          config[:models].include?(model)
        end

        def list_providers
          PROVIDERS.keys
        end

        def list_models(provider)
          config = get(provider)
          config ? config[:models] : []
        end
      end
    end
  end
end
