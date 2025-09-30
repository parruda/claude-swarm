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
require "concurrent"
require "ruby_llm"
require "thor"

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
loader.push_dir("#{__dir__}/swarm_sdk")
loader.inflector.inflect(
  "cli" => "CLI",
  "llm" => "LLM",
  "sdk" => "SDK",
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
