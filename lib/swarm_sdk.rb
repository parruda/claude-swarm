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
    # @example
    #   SwarmSDK.refresh_models_silently
    #
    # @return [void]
    def refresh_models_silently
      original_level = RubyLLM.logger.level
      RubyLLM.logger.level = Logger::ERROR

      RubyLLM.models.refresh!
    ensure
      RubyLLM.logger.level = original_level
    end

    # Main entry point for DSL
    def build(&block)
      Swarm::Builder.build(&block)
    end
  end
end
