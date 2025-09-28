# frozen_string_literal: true

require "thor"
require "yaml"
require "fileutils"
require "json"

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/claude_swarm/templates")
loader.ignore("#{__dir__}/swarm_core.rb")
loader.ignore("#{__dir__}/swarm_core")
loader.inflector.inflect(
  "cli" => "CLI",
  "openai" => "OpenAI",
)
loader.push_dir(File.expand_path("swarm_core", __dir__))
loader.setup

module SwarmCore
end
