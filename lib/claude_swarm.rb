# frozen_string_literal: true

# External dependencies
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
# Don't autoload provider files - they'll be loaded conditionally
loader.ignore("#{__dir__}/claude_swarm/providers/llm_executor.rb")
loader.ignore("#{__dir__}/claude_swarm/providers/response_normalizer.rb")
loader.inflector.inflect(
  "cli" => "CLI"
)
loader.setup

module ClaudeSwarm
  class Error < StandardError; end

  # Conditionally load provider support if ruby_llm is available
  begin
    require "ruby_llm"
    require_relative "claude_swarm/providers/llm_executor"
    require_relative "claude_swarm/providers/response_normalizer"
  rescue LoadError
    # Provider support not available - that's ok
  end
end
