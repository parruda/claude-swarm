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

module SwarmCLI
end

require "zeitwerk"
loader = Zeitwerk::Loader.new
loader.push_dir("#{__dir__}/swarm_cli", namespace: SwarmCLI)
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
