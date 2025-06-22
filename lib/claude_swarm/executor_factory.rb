# frozen_string_literal: true

module ClaudeSwarm
  # Factory class for creating executor instances based on provider configuration
  class ExecutorFactory
    def self.create(instance_config, calling_instance:, calling_instance_id: nil)
      # Default to anthropic provider if not specified
      provider = instance_config[:provider] || "anthropic"

      # Extract common parameters used by all executors
      common_options = {
        working_directory: instance_config[:directory],
        instance_name: instance_config[:name],
        instance_id: instance_config[:instance_id],
        calling_instance: calling_instance,
        calling_instance_id: calling_instance_id
      }

      if provider == "anthropic"
        # Create ClaudeCodeExecutor for anthropic provider
        ClaudeCodeExecutor.new(
          model: instance_config[:model],
          mcp_config: instance_config[:mcp_config_path],
          vibe: instance_config[:vibe],
          claude_session_id: instance_config[:claude_session_id],
          additional_directories: instance_config[:directories]&.slice(1..) || [],
          **common_options
        )
      else
        # Check if provider support is available
        require_provider_support!

        # Create LlmExecutor for other providers
        Providers::LlmExecutor.new(
          provider: provider,
          model: instance_config[:model],
          api_key_env: instance_config[:api_key_env],
          api_base_env: instance_config[:api_base_env],
          assume_model_exists: instance_config[:assume_model_exists],
          mcp_config: instance_config[:mcp_config_path],
          vibe: instance_config[:vibe],
          additional_directories: instance_config[:directories]&.slice(1..) || [],
          **common_options
        )
      end
    end

    def self.require_provider_support!
      # Check if LlmExecutor is available
      return if defined?(::ClaudeSwarm::Providers::LlmExecutor) && check_ruby_llm_available

      raise Error, <<~MSG
        Multi-provider support is not available.

        To use non-Anthropic models (OpenAI, Google, etc.), install the claude-swarm-providers gem:

          gem install claude-swarm-providers

        Or add to your Gemfile:

          gem 'claude-swarm-providers'

        Then restart your application.
      MSG
    end

    def self.check_ruby_llm_available
      require "ruby_llm"
      true
    rescue LoadError
      false
    end
  end
end
