# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "yaml"

require "reline"
require "pastel"
require "tty-box"
require "tty-screen"
require "tty/link"
require "tty/markdown"
require "tty/option"
require "tty/spinner"
require "tty/spinner/multi"
require "tty/tree"

require "swarm_sdk"

require_relative "swarm_cli/version"

require "zeitwerk"
loader = Zeitwerk::Loader.new
loader.tag = File.basename(__FILE__, ".rb")
loader.push_dir("#{__dir__}/swarm_cli", namespace: SwarmCLI)
loader.inflector = Zeitwerk::GemInflector.new(__FILE__)
loader.inflector.inflect(
  "cli" => "CLI",
  "ui" => "UI",
  "interactive_repl" => "InteractiveREPL",
)
loader.setup

module SwarmCLI
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ExecutionError < Error; end
end

# Try to load swarm_memory gem if available (for CLI command extensions)
begin
  require "swarm_memory"
rescue LoadError
  # swarm_memory not installed - that's fine, memory commands won't be available
end
