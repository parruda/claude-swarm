# frozen_string_literal: true

require "test_helper"

class IntegrationRestorationTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir
    @config_path = File.join(@test_dir, "claude-swarm.yml")

    # Create a test configuration
    File.write(@config_path, <<~YAML)
      version: 1
      swarm:
        name: "Integration Test Swarm"
        main: coordinator
        instances:
          coordinator:
            description: "Main coordinator"
            directory: #{@test_dir}
            model: sonnet
            connections: [assistant]
          assistant:
            description: "Assistant worker"#{"  "}
            directory: #{@test_dir}
            model: sonnet
    YAML
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def test_full_restoration_flow
    # Simulate initial run - create session
    session_path = File.join(@test_dir, "test_session")
    FileUtils.mkdir_p(session_path)
    ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    # Save swarm config path
    File.write(File.join(session_path, "swarm_config_path"), @config_path)

    # Generate initial MCP configs
    generator.generate_all

    # Get the generated instance IDs from MCP configs
    coord_mcp = JSON.parse(File.read(File.join(session_path, "coordinator.mcp.json")))
    assist_mcp = JSON.parse(File.read(File.join(session_path, "assistant.mcp.json")))

    coord_instance_id = coord_mcp["instance_id"]
    assist_instance_id = assist_mcp["instance_id"]

    # Simulate instances writing their session IDs using instance_id
    state_dir = File.join(session_path, "state")
    FileUtils.mkdir_p(state_dir)

    File.write(File.join(state_dir, "#{coord_instance_id}.json"), JSON.pretty_generate({
      "instance_name" => "coordinator",
      "instance_id" => coord_instance_id,
      "claude_session_id" => "coord-session-111",
      "status" => "active",
      "updated_at" => Time.now.iso8601,
    }))

    File.write(File.join(state_dir, "#{assist_instance_id}.json"), JSON.pretty_generate({
      "instance_name" => "assistant",
      "instance_id" => assist_instance_id,
      "claude_session_id" => "assist-session-222",
      "status" => "active",
      "updated_at" => Time.now.iso8601,
    }))

    # Now simulate restoration
    restore_generator = ClaudeSwarm::McpGenerator.new(config, restore_session_path: session_path)
    restore_generator.generate_all

    # Check the regenerated configs
    coord_mcp = JSON.parse(File.read(File.join(session_path, "coordinator.mcp.json")))
    assistant_server = coord_mcp["mcpServers"]["assistant"]

    # Verify session ID is in the args
    assert(assistant_server, "Assistant server not found")
    args = assistant_server["args"]

    assert_includes(args, "--claude-session-id", "Missing --claude-session-id flag")
    idx = args.index("--claude-session-id")

    assert_equal("assist-session-222", args[idx + 1], "Wrong session ID")

    # Verify the main instance would get its session ID
    restore_orchestrator = ClaudeSwarm::Orchestrator.new(
      config,
      restore_generator,
      restore_session_path: session_path,
    )

    # The orchestrator should have the restore path
    assert_equal(session_path, restore_orchestrator.instance_variable_get(:@restore_session_path))
  end

  def test_cli_instance_config_includes_session_id
    # Test that CLI properly passes session ID to MCP server
    session_path = File.join(@test_dir, "cli_test_session")
    state_dir = File.join(session_path, "state")
    FileUtils.mkdir_p(state_dir)

    # Write a state file using instance_id
    File.write(File.join(state_dir, "worker_abc123.json"), JSON.pretty_generate({
      "instance_name" => "worker",
      "instance_id" => "worker_abc123",
      "claude_session_id" => "worker-cli-333",
      "status" => "active",
      "updated_at" => Time.now.iso8601,
    }))

    # Simulate CLI options for mcp-serve
    options = {
      name: "worker",
      directory: @test_dir,
      model: "sonnet",
      claude_session_id: "worker-cli-333",
    }

    instance_config = {
      name: options[:name],
      directory: options[:directory],
      model: options[:model],
      prompt: options[:prompt],
      description: options[:description],
      tools: options[:allowed_tools] || [],
      disallowed_tools: options[:disallowed_tools] || [],
      mcp_config_path: options[:mcp_config_path],
      vibe: options[:vibe],
      instance_id: options[:instance_id],
      claude_session_id: options[:claude_session_id],
    }

    # Verify the session ID is included
    assert_equal("worker-cli-333", instance_config[:claude_session_id])
  end
end
