# frozen_string_literal: true

require "test_helper"
require "fixtures/swarm_configs"

class BackwardCompatibilityTest < Minitest::Test
  def setup
    @config_file = Tempfile.new(["claude-swarm", ".yml"])
    @config_file.write(SWARM_CONFIGS[:valid])
    @config_file.rewind
    @config_file.close

    # Clear any registered extensions
    ClaudeSwarm::Extensions.instance_variable_set(:@extensions, {})
    ClaudeSwarm::Extensions.instance_variable_set(:@hooks, {})
  end

  def teardown
    @config_file.unlink
  end

  def test_configuration_loads_without_extensions
    config = ClaudeSwarm::Configuration.new(@config_file.path)
    
    assert_equal 1, config.version
    assert_equal "Development Team", config.swarm_name
    assert_equal "lead", config.main_instance
    assert_equal 3, config.instances.size
  end

  def test_mcp_generation_works_without_extensions
    config = ClaudeSwarm::Configuration.new(@config_file.path)
    session_id = "test-session"
    
    Dir.mktmpdir do |tmpdir|
      generator = ClaudeSwarm::McpGenerator.new(config, session_id, tmpdir)
      generator.generate
      
      # Check that MCP files are generated
      mcp_dir = File.join(tmpdir, ".claude-swarm", session_id)
      assert File.exist?(File.join(mcp_dir, "mcp-claude-swarm.json"))
      assert File.exist?(File.join(mcp_dir, "mcp-backend.json"))
      assert File.exist?(File.join(mcp_dir, "mcp-frontend.json"))
    end
  end

  def test_orchestrator_initialization_without_extensions
    config = ClaudeSwarm::Configuration.new(@config_file.path)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, session_id: "test-session")
    
    assert_equal config, orchestrator.instance_variable_get(:@config)
    assert_equal "test-session", orchestrator.instance_variable_get(:@session_id)
  end

  def test_cli_commands_work_without_extensions
    # Test that CLI commands don't require extensions
    cli = ClaudeSwarm::CLI.new
    
    # Test help command
    output = capture_io { cli.help }
    assert_match(/claude-swarm commands/, output[0])
    
    # Test version command
    output = capture_io { cli.version }
    assert_match(/\d+\.\d+\.\d+/, output[0])
  end

  def test_worktree_manager_works_without_extensions
    Dir.mktmpdir do |tmpdir|
      # Create a mock git repo
      repo_dir = File.join(tmpdir, "test_repo")
      FileUtils.mkdir_p(File.join(repo_dir, ".git"))
      
      manager = ClaudeSwarm::WorktreeManager.new
      
      # Test worktree creation
      worktree_name = "test-worktree"
      worktree_path = manager.create_worktree(repo_dir, worktree_name)
      
      expected_path = File.join(repo_dir, ".worktrees", worktree_name)
      assert_equal expected_path, worktree_path
    end
  end

  def test_session_restoration_without_extensions
    config = ClaudeSwarm::Configuration.new(@config_file.path)
    session_id = "test-restore"
    
    Dir.mktmpdir do |tmpdir|
      # Create session metadata
      session_dir = File.join(tmpdir, ".claude-swarm", session_id)
      FileUtils.mkdir_p(session_dir)
      
      metadata = {
        session_id: session_id,
        created_at: Time.now.to_s,
        config_path: @config_file.path,
        working_directory: Dir.pwd
      }
      
      File.write(File.join(session_dir, "session.json"), JSON.pretty_generate(metadata))
      
      # Test restoration
      restored_metadata = nil
      Dir.chdir(tmpdir) do
        ClaudeSwarm::Orchestrator.new(config, session_id: session_id).instance_eval do
          restored_metadata = restore_session_metadata
        end
      end
      
      assert_equal session_id, restored_metadata["session_id"]
      assert_equal @config_file.path, restored_metadata["config_path"]
    end
  end

  def test_existing_integration_without_extensions
    # Test that the core integration between components works
    config = ClaudeSwarm::Configuration.new(@config_file.path)
    session_id = "integration-test"
    
    Dir.mktmpdir do |tmpdir|
      # Generate MCP configs
      generator = ClaudeSwarm::McpGenerator.new(config, session_id, tmpdir)
      generator.generate
      
      # Verify lead instance has correct connections
      mcp_file = File.join(tmpdir, ".claude-swarm", session_id, "mcp-claude-swarm.json")
      mcp_config = JSON.parse(File.read(mcp_file))
      
      assert_equal 2, mcp_config["mcpServers"].size
      assert mcp_config["mcpServers"].key?("backend")
      assert mcp_config["mcpServers"].key?("frontend")
      
      # Verify backend config
      backend_config = mcp_config["mcpServers"]["backend"]
      assert_equal "stdio", backend_config["transport"]["type"]
      assert_includes backend_config["transport"]["command"]["args"], "-p"
      assert_includes backend_config["transport"]["command"]["args"], "You are a backend developer"
    end
  end

  def test_configuration_validation_without_extensions
    # Test invalid config
    invalid_config = Tempfile.new(["invalid", ".yml"])
    invalid_config.write("invalid: yaml: content: [[[")
    invalid_config.close
    
    assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Configuration.new(invalid_config.path)
    end
    
    invalid_config.unlink
  end

  def test_tool_restrictions_without_extensions
    config = ClaudeSwarm::Configuration.new(@config_file.path)
    
    # Verify tool restrictions work
    lead = config.instances["lead"]
    assert_equal ["Read", "Edit", "Bash", "mcp__backend", "mcp__frontend"], lead.tools
    
    backend = config.instances["backend"]
    assert_equal ["Read", "Write", "Bash"], backend.tools
  end

  def test_vibe_mode_without_extensions
    vibe_config = Tempfile.new(["vibe", ".yml"])
    vibe_config.write(<<~YAML)
      version: 1
      swarm:
        name: "Vibe Test"
        main: lead
        vibe: true
        instances:
          lead:
            description: "Lead"
            directory: .
    YAML
    vibe_config.close
    
    config = ClaudeSwarm::Configuration.new(vibe_config.path)
    assert config.vibe_mode?
    
    # MCP generation should be disabled in vibe mode
    Dir.mktmpdir do |tmpdir|
      generator = ClaudeSwarm::McpGenerator.new(config, "vibe-session", tmpdir)
      generator.generate
      
      # No MCP files should be created
      mcp_dir = File.join(tmpdir, ".claude-swarm", "vibe-session")
      refute File.exist?(mcp_dir)
    end
    
    vibe_config.unlink
  end

  private

  def capture_io
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    
    yield
    
    [$stdout.string, $stderr.string]
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
end