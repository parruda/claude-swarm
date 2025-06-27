# frozen_string_literal: true

# External dependencies
require "time"
require "thor"
require "yaml"
require "json"
require "fileutils"
require "erb"
require "tmpdir"
require "open3"
require "timeout"
require "pty"
require "io/console"

# Zeitwerk setup
require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/claude_swarm/templates")
loader.inflector.inflect(
  "cli" => "CLI",
  "openai_executor" => "OpenAIExecutor"
)
loader.setup

module ClaudeSwarm
  class Error < StandardError; end
end
