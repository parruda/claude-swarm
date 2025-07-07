# frozen_string_literal: true

require "test_helper"

class McpGeneratorArgsTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @session_path = File.join(@tmpdir, "test_session")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path

    @config_content = <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer instance"
            directory: .
            model: opus
            connections: [backend]
            tools: [Read, Edit]
            prompt: "You are the lead"
          backend:
            description: "Backend developer instance"
            directory: ./backend
            model: sonnet
            tools: [Bash, Grep]
            prompt: "You are a backend dev"
    YAML
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def test_mcp_config_generates_correct_args
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        # Write the config file
        File.write("claude-swarm.yml", @config_content)

        # Create required directories
        Dir.mkdir("backend")

        # Create the configuration and generator
        config = ClaudeSwarm::Configuration.new("claude-swarm.yml")
        generator = ClaudeSwarm::McpGenerator.new(config)

        # Generate MCP configs
        generator.generate_all

        # Read the lead instance MCP config
        lead_config = read_mcp_config("lead")

        # Check that backend connection uses correct args format
        backend_mcp = lead_config["mcpServers"]["backend"]

        assert_equal("stdio", backend_mcp["type"])
        assert_equal("claude-swarm", backend_mcp["command"])

        # Verify the args array
        args = backend_mcp["args"]

        # Should start with mcp-serve command
        assert_equal("mcp-serve", args[0])

        # Should have pairs of flag and value
        assert_includes(args, "--name")
        assert_includes(args, "backend")
        assert_includes(args, "--directory")
        assert_includes(args, File.expand_path("./backend"))
        assert_includes(args, "--model")
        assert_includes(args, "sonnet")
        assert_includes(args, "--prompt")
        assert_includes(args, "You are a backend dev")
        assert_includes(args, "--allowed-tools")

        # Tools should be after --allowed-tools flag as comma-separated
        tools_index = args.index("--allowed-tools")

        assert_equal("Bash,Grep", args[tools_index + 1])

        # Should include MCP config path
        assert_includes(args, "--mcp-config-path")
        assert(args[args.index("--mcp-config-path") + 1].end_with?("backend.mcp.json"))
      end
    end
  end

  def test_mcp_config_with_openai_provider_args
    openai_config = <<~YAML
      version: 1
      swarm:
        name: "OpenAI Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead developer"
            directory: .
            model: opus
            connections: [ai_helper]
          ai_helper:
            description: "AI helper using OpenAI"
            directory: .
            provider: openai
            model: gpt-4o
            temperature: 0.7
            api_version: responses
            openai_token_env: CUSTOM_OPENAI_KEY
            base_url: https://custom.openai.com/v1
    YAML

    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        # Write the config file
        File.write("claude-swarm.yml", openai_config)

        # Set environment variable for test
        ENV["CUSTOM_OPENAI_KEY"] = "sk-test-key"

        # Create the configuration and generator
        config = ClaudeSwarm::Configuration.new("claude-swarm.yml")
        generator = ClaudeSwarm::McpGenerator.new(config)

        # Generate MCP configs
        generator.generate_all

        # Read the lead instance MCP config
        lead_config = read_mcp_config("lead")

        # Check that ai_helper connection includes OpenAI provider args
        ai_helper_mcp = lead_config["mcpServers"]["ai_helper"]
        args = ai_helper_mcp["args"]

        # Should include provider and OpenAI-specific args
        assert_includes(args, "--provider")
        assert_includes(args, "openai")
        assert_includes(args, "--temperature")
        assert_includes(args, "0.7")
        assert_includes(args, "--api-version")
        assert_includes(args, "responses")
        assert_includes(args, "--openai-token-env")
        assert_includes(args, "CUSTOM_OPENAI_KEY")
        assert_includes(args, "--base-url")
        assert_includes(args, "https://custom.openai.com/v1")

        # Should have vibe flag for OpenAI instances
        assert_includes(args, "--vibe")
      end
    end
  end

  def test_mcp_config_without_provider_no_openai_args
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        # Write the config file (default Claude provider)
        File.write("claude-swarm.yml", @config_content)

        # Create required directories
        Dir.mkdir("backend")

        # Create the configuration and generator
        config = ClaudeSwarm::Configuration.new("claude-swarm.yml")
        generator = ClaudeSwarm::McpGenerator.new(config)

        # Generate MCP configs
        generator.generate_all

        # Read the lead instance MCP config
        lead_config = read_mcp_config("lead")

        # Check that backend connection doesn't have OpenAI args
        backend_mcp = lead_config["mcpServers"]["backend"]
        args = backend_mcp["args"]

        # Should NOT include OpenAI-specific args
        refute_includes(args, "--provider")
        refute_includes(args, "--temperature")
        refute_includes(args, "--api-version")
        refute_includes(args, "--openai-token-env")
        refute_includes(args, "--base-url")
      end
    end
  ensure
    ENV.delete("CUSTOM_OPENAI_KEY")
  end
end
