# frozen_string_literal: true

require "test_helper"
require "claude_swarm/mcp_generator"
require "claude_swarm/configuration"
require "tmpdir"
require "json"

class McpGeneratorLlmMcpTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
    @mcp_dir = File.join(@tmpdir, ".claude-swarm")

    # Set the session path environment variable
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @mcp_dir
    FileUtils.mkdir_p(@mcp_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def test_llm_mcp_instance_gets_claude_mcp_server
    # Create required directories
    FileUtils.mkdir_p(File.join(@tmpdir, "src"))

    config_content = <<~YAML
      version: 1
      swarm:
        name: "Multi-Model Swarm"
        main: architect
        instances:
          architect:
            description: "Main architect using Claude"
            directory: .
            model: sonnet
            connections: [openai_helper]
          openai_helper:
            description: "OpenAI powered assistant"
            directory: ./src
            provider: openai
            model: gpt-4
            base_url: https://api.openai.com/v1
            prompt: "You are an OpenAI assistant"
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Debug output
    puts "\nMCP dir: #{@mcp_dir}"
    puts "Session path from env: #{ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil)}"
    puts "\nGenerated files in session dir:"
    Dir.glob(File.join(@mcp_dir, "**/*")).each do |f|
      puts "  #{f}" if File.file?(f)
    end

    # Check that OpenAI instance has Claude MCP server in its llm-mcp connections file
    openai_mcp_path = File.join(@mcp_dir, "openai_helper.mcp.json")

    assert_path_exists openai_mcp_path, "MCP config for openai_helper should exist"

    # Check the regular MCP config to understand the structure
    openai_config = JSON.parse(File.read(openai_mcp_path))
    puts "\nOpenAI helper MCP config:"
    puts JSON.pretty_generate(openai_config)

    # Check the llm-mcp connections file
    llm_mcp_config_path = File.join(@mcp_dir, "openai_helper_llm_mcp_connections.json")

    assert_path_exists llm_mcp_config_path, "LLM-MCP connections config should exist"

    llm_mcp_config = JSON.parse(File.read(llm_mcp_config_path))

    assert llm_mcp_config["mcpServers"].key?("tools"), "OpenAI instance should have Claude MCP server"
    refute llm_mcp_config["mcpServers"].key?("architect"), "OpenAI instance should not have connection to architect since architect connects to it"

    claude_server = llm_mcp_config["mcpServers"]["tools"]

    assert_equal "stdio", claude_server["type"]
    assert_equal "claude", claude_server["command"]
    assert_equal %w[mcp serve], claude_server["args"]
  end

  def test_claude_instance_does_not_get_claude_mcp_server
    config_content = <<~YAML
      version: 1
      swarm:
        name: "Claude Only Swarm"
        main: leader
        instances:
          leader:
            description: "Claude leader"
            directory: .
            model: opus
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check that Claude instance does NOT have Claude MCP server
    leader_mcp_path = File.join(@mcp_dir, "leader.mcp.json")

    assert_path_exists leader_mcp_path, "MCP config for leader should exist"

    mcp_config = JSON.parse(File.read(leader_mcp_path))

    refute mcp_config["mcpServers"].key?("tools"), "Claude instance should not have Claude MCP server"
  end

  def test_anthropic_provider_does_not_get_claude_mcp_server
    config_content = <<~YAML
      version: 1
      swarm:
        name: "Anthropic Provider Swarm"
        main: leader
        instances:
          leader:
            description: "Leader with explicit anthropic provider"
            directory: .
            provider: anthropic
            model: sonnet
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check that instance with provider: anthropic does NOT get Claude MCP server
    leader_mcp_path = File.join(@mcp_dir, "leader.mcp.json")

    assert_path_exists leader_mcp_path, "MCP config for leader should exist"

    mcp_config = JSON.parse(File.read(leader_mcp_path))

    refute mcp_config["mcpServers"].key?("tools"), "Instance with provider: anthropic should not have Claude MCP server"
  end

  def test_llm_mcp_instance_without_connections_gets_tools
    config_content = <<~YAML
      version: 1
      swarm:
        name: "Simple LLM Swarm"
        main: leader
        instances:
          leader:
            description: "Claude leader"
            directory: .
            model: sonnet
            connections: [gemini_helper]
          gemini_helper:
            description: "Gemini standalone helper"
            directory: .
            provider: google
            model: gemini-pro
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check that Gemini instance has llm-mcp connections file with tools
    llm_mcp_config_path = File.join(@mcp_dir, "gemini_helper_llm_mcp_connections.json")

    assert_path_exists llm_mcp_config_path, "LLM-MCP connections config should exist"

    llm_mcp_config = JSON.parse(File.read(llm_mcp_config_path))

    assert llm_mcp_config["mcpServers"].key?("tools"), "Gemini instance should have Claude MCP server"
    refute llm_mcp_config["mcpServers"].key?("leader"), "Gemini instance should not have connection to leader"
  end
end
