# frozen_string_literal: true

require "bundler"
require "digest"
require "English"
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
require "thor"

module SwarmSDK
end

require "zeitwerk"
loader = Zeitwerk::Loader.new
loader.push_dir("#{__dir__}/swarm_sdk", namespace: SwarmSDK)
loader.inflector.inflect(
  "cli" => "CLI",
  "llm_manager" => "LLMManager",
)
loader.setup

module SwarmSDK
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class AgentNotFoundError < Error; end
  class CircularDependencyError < Error; end
  class ToolExecutionError < Error; end
  class LLMError < Error; end

  class << self
    def root_dir
      ENV.fetch("SWARM_ROOT_DIR") { Dir.pwd }
    end

    def home_dir
      ENV.fetch("CLAUDE_SWARM_HOME") { File.expand_path("~/.claude-swarm") }
    end

    def joined_home_dir(*strings)
      File.join(home_dir, *strings)
    end

    def joined_sessions_dir(*strings)
      joined_home_dir("sessions", *strings)
    end
  end
end
