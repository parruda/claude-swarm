# frozen_string_literal: true

require "test_helper"

class SessionRestorationTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir
    @config_path = File.join(@test_dir, "claude-swarm.yml")

    # Create a test configuration
    File.write(@config_path, <<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            directory: .
            model: sonnet
            connections: [worker]
          worker:
            description: "Worker instance"#{"  "}
            directory: .
            model: sonnet
    YAML
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def test_mcp_config_includes_session_id_on_restoration
    # Create a session with states
    session_path = File.join(@test_dir, "sessions", "test_project", "20240101_120000")
    FileUtils.mkdir_p(session_path)

    # Save swarm config path
    File.write(File.join(session_path, "swarm_config_path"), @config_path)

    # Write instance states
    state_dir = File.join(session_path, "state")
    FileUtils.mkdir_p(state_dir)

    File.write(File.join(state_dir, "lead_abc123.json"), JSON.pretty_generate({
      "instance_name" => "lead",
      "instance_id" => "lead_abc123",
      "claude_session_id" => "lead-session-123",
      "status" => "active",
      "updated_at" => Time.now.iso8601,
    }))

    File.write(File.join(state_dir, "worker_def456.json"), JSON.pretty_generate({
      "instance_name" => "worker",
      "instance_id" => "worker_def456",
      "claude_session_id" => "worker-session-456",
      "status" => "active",
      "updated_at" => Time.now.iso8601,
    }))

    # Load configuration
    config = ClaudeSwarm::Configuration.new(@config_path)

    # Create generator with restore session path
    ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path
    generator = ClaudeSwarm::McpGenerator.new(config, restore_session_path: session_path)
    generator.generate_all

    # Check the generated MCP configs
    lead_mcp = JSON.parse(File.read(File.join(session_path, "lead.mcp.json")))

    # Find the worker MCP server config in lead's config
    worker_server = lead_mcp["mcpServers"]["worker"]

    assert(worker_server, "Worker server not found in lead's MCP config")

    # Check that the args include --claude-session-id
    assert_includes(
      worker_server["args"],
      "--claude-session-id",
      "Missing --claude-session-id in args: #{worker_server["args"].inspect}",
    )

    session_id_index = worker_server["args"].index("--claude-session-id")

    assert_equal(
      "worker-session-456",
      worker_server["args"][session_id_index + 1],
      "Wrong session ID in args",
    )
  end
end
