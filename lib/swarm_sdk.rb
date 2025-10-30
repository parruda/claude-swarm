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

require_relative "swarm_sdk/version"

require "zeitwerk"
loader = Zeitwerk::Loader.new
loader.tag = File.basename(__FILE__, ".rb")
loader.push_dir("#{__dir__}/swarm_sdk", namespace: SwarmSDK)
loader.inflector = Zeitwerk::GemInflector.new(__FILE__)
loader.inflector.inflect(
  "cli" => "CLI",
  "openai_with_responses" => "OpenAIWithResponses",
)
loader.setup

# Load plugin system explicitly (core infrastructure)
require_relative "swarm_sdk/plugin"
require_relative "swarm_sdk/plugin_registry"

module SwarmSDK
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class AgentNotFoundError < Error; end
  class CircularDependencyError < Error; end
  class ToolExecutionError < Error; end
  class LLMError < Error; end
  class StateError < Error; end

  class << self
    # Settings for SwarmSDK (global configuration)
    attr_accessor :settings

    # Main entry point for DSL
    def build(&block)
      Swarm::Builder.build(&block)
    end

    # Configure SwarmSDK global settings
    def configure
      self.settings ||= Settings.new
      yield(settings)
    end

    # Reset settings to defaults
    def reset_settings!
      self.settings = Settings.new
    end

    # Alias for backward compatibility
    alias_method :configuration, :settings
    alias_method :reset_configuration!, :reset_settings!
  end

  # Settings class for SwarmSDK global settings (not to be confused with Configuration for YAML loading)
  class Settings
    # WebFetch tool LLM processing configuration
    attr_accessor :webfetch_provider, :webfetch_model, :webfetch_base_url, :webfetch_max_tokens

    def initialize
      @webfetch_provider = nil
      @webfetch_model = nil
      @webfetch_base_url = nil
      @webfetch_max_tokens = 4096
    end

    # Check if WebFetch LLM processing is enabled
    def webfetch_llm_enabled?
      !@webfetch_provider.nil? && !@webfetch_model.nil?
    end
  end

  # Initialize default settings
  self.settings = Settings.new
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

# monkey patches
# ruby_llm/mcp
# - add `id` when sending "notifications/initialized" message: https://github.com/patvice/ruby_llm-mcp/issues/65
# - remove `to_sym` on MCP parameter type: https://github.com/patvice/ruby_llm-mcp/issues/62#issuecomment-3421488406
require "ruby_llm/mcp/notifications/initialize"
require "ruby_llm/mcp/parameter"

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
