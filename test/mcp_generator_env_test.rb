# frozen_string_literal: true

require "test_helper"

class McpGeneratorEnvTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
    @session_path = File.join(@tmpdir, "test_session")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path

    # Set up test environment variables
    ENV["BUNDLE_TEST_VAR"] = "bundle_test"
    ENV["RUBY_TEST_VAR"] = "ruby_test"
    ENV["GEM_TEST_HOME"] = "gem_test"
    ENV["RUBYOPT"] = "-W0"
    ENV["NORMAL_VAR"] = "should_remain"
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
    ENV.delete("BUNDLE_TEST_VAR")
    ENV.delete("RUBY_TEST_VAR")
    ENV.delete("GEM_TEST_HOME")
    ENV.delete("RUBYOPT")
    ENV.delete("NORMAL_VAR")
  end

  def test_claude_tools_mcp_config_filters_ruby_env
    # Set up config with OpenAI provider instance to trigger claude_tools generation
    config_yaml = <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            connections: [openai_instance]
          openai_instance:
            description: "OpenAI instance"
            provider: openai
            model: gpt-4
    YAML

    File.write(@config_path, config_yaml)
    ENV["OPENAI_API_KEY"] = "test-key"

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      # Read the generated MCP config
      config_file = File.join(@session_path, "openai_instance.mcp.json")

      assert_path_exists(config_file, "MCP config file should exist")

      mcp_config = JSON.parse(File.read(config_file))

      # Check claude_tools MCP server environment
      assert(mcp_config["mcpServers"]["claude_tools"], "Should have claude_tools server")
      claude_tools_env = mcp_config["mcpServers"]["claude_tools"]["env"]

      # Verify Ruby/Bundle vars are filtered out
      refute(claude_tools_env.key?("BUNDLE_TEST_VAR"), "BUNDLE vars should be filtered")
      refute(claude_tools_env.key?("RUBY_TEST_VAR"), "RUBY vars should be filtered")
      refute(claude_tools_env.key?("GEM_TEST_HOME"), "GEM vars should be filtered")
      refute(claude_tools_env.key?("RUBYOPT"), "RUBYOPT should be filtered")

      # Verify normal vars remain
      assert_equal("should_remain", claude_tools_env["NORMAL_VAR"], "Normal vars should remain")
    end
  ensure
    ENV.delete("OPENAI_API_KEY")
  end

  def test_instance_mcp_config_preserves_ruby_env
    # Set up config with connected instances
    config_yaml = <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            connections: [worker]
          worker:
            description: "Worker instance"
    YAML

    File.write(@config_path, config_yaml)

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      # Read the generated MCP config for lead instance
      config_file = File.join(@session_path, "lead.mcp.json")
      mcp_config = JSON.parse(File.read(config_file))

      # Check worker MCP server environment
      worker_env = mcp_config["mcpServers"]["worker"]["env"]

      # Verify Ruby/Bundle vars are preserved for claude-swarm mcp-serve
      assert_equal("bundle_test", worker_env["BUNDLE_TEST_VAR"], "BUNDLE vars should be preserved")
      assert_equal("-W0", worker_env["RUBYOPT"], "RUBYOPT should be preserved")
    end
  end
end
