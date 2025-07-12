# frozen_string_literal: true

# Standard library dependencies
require "digest"
require "English"
require "erb"
require "fileutils"
require "io/console"
require "json"
require "logger"
require "open3"
require "pathname"
require "pty"
require "securerandom"
require "set"
require "shellwords"
require "time"
require "timeout"
require "tmpdir"
require "yaml"

# External dependencies
require "fast_mcp_annotations"
require "mcp_client"
require "openai"
require "thor"

# Zeitwerk setup
require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.ignore("#{__dir__}/claude_swarm/templates")
loader.inflector.inflect(
  "cli" => "CLI",
  "openai" => "OpenAI",
)
loader.setup

module ClaudeSwarm
  class Error < StandardError; end

  class << self
    def root_dir
      ENV.fetch("CLAUDE_SWARM_ROOT_DIR", Dir.pwd)
    end

    def with_clean_environment(&block)
      # Use Bundler's unbundled environment as a base
      Bundler.with_unbundled_env do
        # Additionally clean Ruby-specific variables that might interfere
        original_env = {}
        vars_to_clean = ["RUBYOPT", "RUBYLIB", "GEM_HOME", "GEM_PATH"]

        vars_to_clean.each do |var|
          if ENV.key?(var)
            original_env[var] = ENV[var]
            ENV.delete(var)
          end
        end

        begin
          yield
        ensure
          # Restore original values
          original_env.each do |var, value|
            ENV[var] = value
          end
        end
      end
    end

    def clean_env_hash
      # Returns a hash with Ruby/Bundler-specific variables removed
      # Used for passing to child processes
      ENV.to_h.reject do |key, _|
        key.start_with?("BUNDLE_") ||
          key.start_with?("RUBY") ||
          key.start_with?("GEM_") ||
          key == "RUBYOPT" ||
          key == "RUBYLIB"
      end
    end
  end
end
