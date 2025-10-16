# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))

require "swarm_sdk"
require "minitest/autorun"
require "stringio"
require "tmpdir"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

module SwarmSDK
  module TestHelpers
    def silence_output
      original_stdout = $stdout
      original_stderr = $stderr
      $stdout = StringIO.new
      $stderr = StringIO.new
      yield
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end

    def with_temp_dir(&block)
      Dir.mktmpdir("swarm_sdk_test", &block)
    end

    def with_temp_config(content)
      with_temp_dir do |dir|
        config_path = File.join(dir, "swarm.yml")
        File.write(config_path, content)
        yield config_path, dir
      end
    end

    # Helper to create agent definitions with sensible defaults for testing
    #
    # @param name [Symbol, String] Agent name
    # @param config [Hash] Agent configuration (optional fields)
    # @return [Agent::Definition] Fully configured agent definition
    #
    # @example
    #   swarm.add_agent(create_agent(name: :test))
    #   swarm.add_agent(create_agent(name: :backend, tools: [:Read, :Write]))
    def create_agent(name:, **config)
      # Provide sensible defaults for testing
      config[:description] ||= "Test agent #{name}"
      config[:model] ||= "gpt-5"
      config[:system_prompt] ||= "Test"
      config[:directories] ||= ["."]

      SwarmSDK::Agent::Definition.new(name, config)
    end
  end
end

Minitest::Test.include(SwarmSDK::TestHelpers)

original_home_dir = ENV["CLAUDE_SWARM_HOME"]
test_swarm_home = Dir.mktmpdir("swarm-sdk-test")
ENV["CLAUDE_SWARM_HOME"] = test_swarm_home

Minitest.after_run do
  FileUtils.rm_rf(test_swarm_home)
  ENV["CLAUDE_SWARM_HOME"] = original_home_dir
end
