# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "claude_swarm"

require "minitest/autorun"
require_relative "fixtures/swarm_configs"
require_relative "helpers/test_helpers"

# Helper module for provider-related tests
module ProviderTestHelper
  # Check if ruby_llm is available for provider tests
  def self.ruby_llm_available?
    require "ruby_llm"
    true
  rescue LoadError
    false
  end

  def skip_unless_ruby_llm_available
    skip "ruby_llm gem not available - install claude-swarm-providers to run provider tests" unless ProviderTestHelper.ruby_llm_available?
  end
end

# Include the helper in all tests
module Minitest
  class Test
    include ProviderTestHelper
  end
end

# Set up a temporary home directory for all tests
require "tmpdir"
TEST_SWARM_HOME = Dir.mktmpdir("claude-swarm-test")
ENV["CLAUDE_SWARM_HOME"] = TEST_SWARM_HOME

# Clean up the test home directory after all tests
Minitest.after_run do
  FileUtils.rm_rf(TEST_SWARM_HOME)
end
