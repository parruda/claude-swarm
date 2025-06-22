# frozen_string_literal: true

module ClaudeSwarm
  module Providers
    # Registry of provider capabilities for different LLM providers
    module Capabilities
      # Defines what features each provider supports and their limits
      REGISTRY = {
        "anthropic" => {
          supports_streaming: true,
          supports_tools: true,
          supports_system_prompt: true,
          max_context: 200_000,
          tool_format: :xml,
          supports_custom_base: false
        },
        "openai" => {
          supports_streaming: true,
          supports_tools: true,
          supports_system_prompt: true,
          max_context: 128_000,
          tool_format: :json,
          supports_custom_base: true
        },
        "google" => {
          supports_streaming: true,
          supports_tools: false, # Not via RubyLLM yet
          supports_system_prompt: true,
          max_context: 2_000_000,
          tool_format: nil,
          supports_custom_base: false
        },
        "cohere" => {
          supports_streaming: true,
          supports_tools: true,
          supports_system_prompt: true,
          max_context: 128_000,
          tool_format: :json,
          supports_custom_base: false
        }
      }.freeze

      # Check if a provider supports a specific capability
      #
      # @param provider [String] The provider name (e.g., "anthropic", "openai")
      # @param capability [Symbol, String] The capability to check (e.g., :supports_tools)
      # @return [Boolean, Integer, Symbol, nil] The capability value or false if not supported
      def self.supports?(provider, capability)
        REGISTRY.dig(provider.to_s, capability.to_sym) || false
      end
    end

    # For backward compatibility and convenience
    CAPABILITIES = Capabilities::REGISTRY

    # Delegate to Capabilities module
    def self.supports?(provider, capability)
      Capabilities.supports?(provider, capability)
    end
  end
end
