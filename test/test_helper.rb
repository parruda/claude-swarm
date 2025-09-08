# frozen_string_literal: true

require "simplecov"
SimpleCov.external_at_exit = true
SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
  add_filter "/vendor/"
  add_filter "/version.rb"
  add_group "Library", "lib"
  track_files "{lib}/**/*.rb"
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "claude_swarm"
require "minitest/autorun"
require_relative "fixtures/swarm_configs"
require_relative "helpers/test_helpers"

# Set up a temporary home directory for all tests
require "tmpdir"
test_swarm_home = Dir.mktmpdir("claude-swarm-test")
original_home_dir = ENV["CLAUDE_SWARM_HOME"]
ENV["CLAUDE_SWARM_HOME"] = test_swarm_home

# Clean up the test home directory after all tests
Minitest.after_run do
  FileUtils.rm_rf(test_swarm_home)
  ENV["CLAUDE_SWARM_HOME"] = original_home_dir
end
