# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
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
TEST_SWARM_HOME = Dir.mktmpdir("claude-swarm-test")
ENV["CLAUDE_SWARM_HOME"] = TEST_SWARM_HOME

# Clean up the test home directory after all tests
Minitest.after_run do
  FileUtils.rm_rf(TEST_SWARM_HOME)
end
