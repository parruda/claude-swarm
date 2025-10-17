# frozen_string_literal: true

require "bundler"
require "digest"
require "English"
require "erb"
require "fileutils"
require "json"
require "logger"
require "pathname"
require "securerandom"
require "set"
require "yaml"

require "async"
require "async/semaphore"
require "ruby_llm"
require "ruby_llm/mcp"

module SwarmSDK
end

require "zeitwerk"
loader = Zeitwerk::Loader.new
loader.push_dir("#{__dir__}/swarm_sdk", namespace: SwarmSDK)
loader.inflector.inflect(
  "cli" => "CLI",
)
loader.setup

# Load custom providers explicitly (Zeitwerk doesn't eager load by default)
require_relative "swarm_sdk/providers/openai_with_responses"

module SwarmSDK
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class AgentNotFoundError < Error; end
  class CircularDependencyError < Error; end
  class ToolExecutionError < Error; end
  class LLMError < Error; end
  class StateError < Error; end

  class << self
    # Refresh RubyLLM model registry silently (without log output)
    #
    # By default, RubyLLM.models.refresh! outputs INFO level logs about
    # fetching models from providers. This method temporarily raises the
    # log level to suppress those messages, which is useful for CLI tools
    # that want clean output.
    #
    # If model refresh fails (e.g., missing API keys, invalid keys, network
    # unavailable), the error is silently caught and execution continues
    # using the bundled models.json. This allows SwarmSDK to work offline
    # and with dummy keys for local proxies.
    #
    # @example
    #   SwarmSDK.refresh_models_silently
    #
    # @return [void]
    def refresh_models_silently
      original_level = RubyLLM.logger.level
      RubyLLM.logger.level = Logger::ERROR

      RubyLLM.models.refresh!
    rescue StandardError => e
      # Silently ignore all refresh failures
      # Models will use bundled models.json instead
      RubyLLM.logger.debug("Model refresh skipped: #{e.class} - #{e.message}")
      nil
    ensure
      RubyLLM.logger.level = original_level
    end

    # Main entry point for DSL
    def build(&block)
      Swarm::Builder.build(&block)
    end
  end
end

# Automatically configure RubyLLM from environment variables
# This makes SwarmSDK "just work" when users set standard ENV variables
RubyLLM.configure do |config|
  # Only set if config not already set (||= handles nil ENV values gracefully)

  # OpenAI
  config.openai_api_key ||= ENV["OPENAI_API_KEY"]
  config.openai_api_base ||= ENV["OPENAI_API_BASE"]
  config.openai_organization_id ||= ENV["OPENAI_ORG_ID"]
  config.openai_project_id ||= ENV["OPENAI_PROJECT_ID"]

  # Anthropic
  config.anthropic_api_key ||= ENV["ANTHROPIC_API_KEY"]

  # Google Gemini
  config.gemini_api_key ||= ENV["GEMINI_API_KEY"]

  # Google Vertex AI (note: vertexai, not vertex_ai)
  config.vertexai_project_id ||= ENV["GOOGLE_CLOUD_PROJECT"] || ENV["VERTEXAI_PROJECT_ID"]
  config.vertexai_location ||= ENV["GOOGLE_CLOUD_LOCATION"] || ENV["VERTEXAI_LOCATION"]

  # DeepSeek
  config.deepseek_api_key ||= ENV["DEEPSEEK_API_KEY"]

  # Mistral
  config.mistral_api_key ||= ENV["MISTRAL_API_KEY"]

  # Perplexity
  config.perplexity_api_key ||= ENV["PERPLEXITY_API_KEY"]

  # OpenRouter
  config.openrouter_api_key ||= ENV["OPENROUTER_API_KEY"]

  # AWS Bedrock
  config.bedrock_api_key ||= ENV["AWS_ACCESS_KEY_ID"]
  config.bedrock_secret_key ||= ENV["AWS_SECRET_ACCESS_KEY"]
  config.bedrock_region ||= ENV["AWS_REGION"]
  config.bedrock_session_token ||= ENV["AWS_SESSION_TOKEN"]

  # Ollama (local)
  config.ollama_api_base ||= ENV["OLLAMA_API_BASE"]

  # GPUStack (local)
  config.gpustack_api_base ||= ENV["GPUSTACK_API_BASE"]
  config.gpustack_api_key ||= ENV["GPUSTACK_API_KEY"]
end

# monkey patch ruby_llm/mcp to add `id` when sending "notifications/initialized" message
# https://github.com/patvice/ruby_llm-mcp/issues/65
require "ruby_llm/mcp/notifications/initialize"

module RubyLLM
  module MCP
    module Notifications
      class Initialize
        def call
          @coordinator.request(notification_body, add_id: true, wait_for_response: false)
        end
      end
    end
  end
end
