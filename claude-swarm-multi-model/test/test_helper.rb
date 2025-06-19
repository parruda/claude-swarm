# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "claude_swarm_multi_model"

# Mock Concurrent module for tests
module Concurrent
  class Array < ::Array
  end
end

# Define ClaudeSwarm module and classes if not already loaded
unless defined?(ClaudeSwarm)
  module ClaudeSwarm
    class Error < StandardError; end

    module Extensions
      class << self
        def register_extension(name, metadata = {})
          # Mock implementation
        end

        def register_hook(hook_name, priority: 50, &block)
          # Mock implementation
        end
      end
    end
  end
end
