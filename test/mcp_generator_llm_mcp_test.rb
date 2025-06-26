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

  def test_llm_mcp_instance_with_temperature
    # Create required directories
    FileUtils.mkdir_p(File.join(@tmpdir, "src"))

    config_content = <<~YAML
      version: 1
      swarm:
        name: "Temperature Test Swarm"
        main: architect
        instances:
          architect:
            description: "Main architect using Claude"
            directory: .
            model: sonnet
            connections: [creative_writer, precise_coder]
          creative_writer:
            description: "Creative writing assistant"
            directory: ./src
            provider: openai
            model: gpt-4
            temperature: 0.9
            prompt: "You are a creative writer"
          precise_coder:
            description: "Precise coding assistant"
            directory: ./src
            provider: google
            model: gemini-pro
            temperature: 0.1
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check architect's MCP config to see how it connects to creative_writer and precise_coder
    architect_mcp_path = File.join(@mcp_dir, "architect.mcp.json")

    assert_path_exists architect_mcp_path

    architect_config = JSON.parse(File.read(architect_mcp_path))

    # Check creative_writer connection with temperature 0.9
    creative_server = architect_config["mcpServers"]["creative_writer"]

    assert_equal "stdio", creative_server["type"]
    assert_equal "llm-mcp", creative_server["command"]
    assert_includes creative_server["args"], "--temperature"

    temp_index = creative_server["args"].index("--temperature")

    assert_equal "0.9", creative_server["args"][temp_index + 1]

    # Check precise_coder connection with temperature 0.1
    precise_server = architect_config["mcpServers"]["precise_coder"]

    assert_includes precise_server["args"], "--temperature"

    temp_index_precise = precise_server["args"].index("--temperature")

    assert_equal "0.1", precise_server["args"][temp_index_precise + 1]
  end

  def test_llm_mcp_instance_without_temperature
    config_content = <<~YAML
      version: 1
      swarm:
        name: "No Temperature Swarm"
        main: architect
        instances:
          architect:
            description: "Main architect"
            directory: .
            model: sonnet
            connections: [assistant]
          assistant:
            description: "Assistant without temperature"
            directory: .
            provider: openai
            model: gpt-4
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check architect's MCP config to see how it connects to assistant
    architect_mcp_path = File.join(@mcp_dir, "architect.mcp.json")

    assert_path_exists architect_mcp_path

    architect_config = JSON.parse(File.read(architect_mcp_path))
    assistant_server = architect_config["mcpServers"]["assistant"]

    refute_includes assistant_server["args"], "--temperature", "Should not include temperature when not specified"
  end

  def test_llm_mcp_instance_with_reasoning_effort
    # Create required directories
    FileUtils.mkdir_p(File.join(@tmpdir, "src"))

    config_content = <<~YAML
      version: 1
      swarm:
        name: "Reasoning Effort Test Swarm"
        main: architect
        instances:
          architect:
            description: "Main architect using Claude"
            directory: .
            model: sonnet
            connections: [o3_low, o3_pro_medium, o4_mini_high]
          o3_low:
            description: "O3 model with low reasoning effort"
            directory: ./src
            provider: openai
            model: o3
            reasoning_effort: low
            prompt: "You are using o3 with low reasoning effort"
          o3_pro_medium:
            description: "O3 Pro model with medium reasoning effort"
            directory: ./src
            provider: openai
            model: o3-pro
            reasoning_effort: medium
          o4_mini_high:
            description: "O4 Mini model with high reasoning effort"
            directory: ./src
            provider: openai
            model: o4-mini
            reasoning_effort: high
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check architect's MCP config to see how it connects to the o3/o4 models
    architect_mcp_path = File.join(@mcp_dir, "architect.mcp.json")

    assert_path_exists architect_mcp_path

    architect_config = JSON.parse(File.read(architect_mcp_path))

    # Check o3_low connection with reasoning effort low
    o3_low_server = architect_config["mcpServers"]["o3_low"]

    assert_equal "stdio", o3_low_server["type"]
    assert_equal "llm-mcp", o3_low_server["command"]
    assert_includes o3_low_server["args"], "--reasoning-effort"

    effort_index = o3_low_server["args"].index("--reasoning-effort")

    assert_equal "low", o3_low_server["args"][effort_index + 1]

    # Check o3_pro_medium connection with reasoning effort medium
    o3_pro_server = architect_config["mcpServers"]["o3_pro_medium"]

    assert_includes o3_pro_server["args"], "--reasoning-effort"

    effort_index_pro = o3_pro_server["args"].index("--reasoning-effort")

    assert_equal "medium", o3_pro_server["args"][effort_index_pro + 1]

    # Check o4_mini_high connection with reasoning effort high
    o4_mini_server = architect_config["mcpServers"]["o4_mini_high"]

    assert_includes o4_mini_server["args"], "--reasoning-effort"

    effort_index_mini = o4_mini_server["args"].index("--reasoning-effort")

    assert_equal "high", o4_mini_server["args"][effort_index_mini + 1]
  end

  def test_llm_mcp_instance_without_reasoning_effort
    config_content = <<~YAML
      version: 1
      swarm:
        name: "No Reasoning Effort Swarm"
        main: architect
        instances:
          architect:
            description: "Main architect"
            directory: .
            model: sonnet
            connections: [o3_assistant]
          o3_assistant:
            description: "O3 assistant without reasoning effort"
            directory: .
            provider: openai
            model: o3
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check architect's MCP config to see how it connects to o3_assistant
    architect_mcp_path = File.join(@mcp_dir, "architect.mcp.json")

    assert_path_exists architect_mcp_path

    architect_config = JSON.parse(File.read(architect_mcp_path))
    o3_assistant_server = architect_config["mcpServers"]["o3_assistant"]

    refute_includes o3_assistant_server["args"], "--reasoning-effort", "Should not include reasoning effort when not specified"
  end

  def test_llm_mcp_instance_with_reasoning_effort_and_temperature
    config_content = <<~YAML
      version: 1
      swarm:
        name: "Combined Test Swarm"
        main: architect
        instances:
          architect:
            description: "Main architect"
            directory: .
            model: sonnet
            connections: [o4_assistant]
          o4_assistant:
            description: "O4 assistant with both temperature and reasoning effort"
            directory: .
            provider: openai
            model: o4-mini-high
            temperature: 0.7
            reasoning_effort: medium
    YAML

    File.write(@config_path, config_content)
    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    generator.generate_all

    # Check architect's MCP config
    architect_mcp_path = File.join(@mcp_dir, "architect.mcp.json")

    assert_path_exists architect_mcp_path

    architect_config = JSON.parse(File.read(architect_mcp_path))
    o4_server = architect_config["mcpServers"]["o4_assistant"]

    # Should have both temperature and reasoning effort
    assert_includes o4_server["args"], "--temperature"
    assert_includes o4_server["args"], "--reasoning-effort"

    temp_index = o4_server["args"].index("--temperature")

    assert_equal "0.7", o4_server["args"][temp_index + 1]

    effort_index = o4_server["args"].index("--reasoning-effort")

    assert_equal "medium", o4_server["args"][effort_index + 1]
  end
end
