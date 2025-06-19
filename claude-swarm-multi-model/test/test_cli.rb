# frozen_string_literal: true

require "test_helper"
require "thor"

class TestCli < Minitest::Test
  def setup
    @cli = ClaudeSwarmMultiModel::CLI.new
    @original_stdout = $stdout
    @original_stderr = $stderr
  end

  def teardown
    $stdout = @original_stdout
    $stderr = @original_stderr
  end

  def test_version_command
    output = capture_output { @cli.version }
    assert_match(/claude-swarm-multi-model version \d+\.\d+\.\d+/, output)
  end

  def test_serve_command_default_options
    # Mock the server to avoid actually starting it
    mock_server = Minitest::Mock.new
    mock_server.expect(:start, nil)

    ClaudeSwarmMultiModel::Mcp::Server.stub :new, mock_server do
      @cli.serve
    end

    mock_server.verify
  end

  def test_serve_command_with_port_option
    skip "Port option implementation pending"
    
    mock_server = Minitest::Mock.new
    mock_server.expect(:start, nil)

    ClaudeSwarmMultiModel::Mcp::Server.stub :new, mock_server do
      @cli.options = { port: 8080 }
      @cli.serve
    end

    mock_server.verify
  end

  def test_list_providers_command
    # Mock provider registry
    mock_providers = {
      "openai" => { name: "OpenAI", models: ["gpt-4", "gpt-3.5-turbo"] },
      "anthropic" => { name: "Anthropic", models: ["claude-3-opus", "claude-3-sonnet"] }
    }

    ClaudeSwarmMultiModel::ProviderRegistry.stub :list_providers, mock_providers do
      output = capture_output { @cli.list_providers }
      
      assert_match(/Available LLM Providers:/, output)
      assert_match(/openai/, output)
      assert_match(/OpenAI/, output)
      assert_match(/gpt-4, gpt-3.5-turbo/, output)
      assert_match(/anthropic/, output)
      assert_match(/Anthropic/, output)
      assert_match(/claude-3-opus, claude-3-sonnet/, output)
    end
  end

  def test_list_providers_with_no_providers
    ClaudeSwarmMultiModel::ProviderRegistry.stub :list_providers, {} do
      output = capture_output { @cli.list_providers }
      assert_match(/No providers available/, output)
    end
  end

  def test_validate_config_command_valid
    valid_config = Tempfile.new(["config", ".yml"])
    valid_config.write(<<~YAML)
      providers:
        openai:
          api_key: "test-key"
          models:
            - gpt-4
            - gpt-3.5-turbo
    YAML
    valid_config.close

    output = capture_output { @cli.validate_config(valid_config.path) }
    
    assert_match(/Configuration is valid/, output)
    assert_match(/Providers found: openai/, output)
    
    valid_config.unlink
  end

  def test_validate_config_command_invalid
    invalid_config = Tempfile.new(["config", ".yml"])
    invalid_config.write(<<~YAML)
      providers:
        invalid_provider:
          missing_required_field: true
    YAML
    invalid_config.close

    output = capture_output(:stderr) do
      assert_raises(SystemExit) { @cli.validate_config(invalid_config.path) }
    end
    
    assert_match(/Configuration validation failed/, output)
    
    invalid_config.unlink
  end

  def test_validate_config_nonexistent_file
    output = capture_output(:stderr) do
      assert_raises(SystemExit) { @cli.validate_config("/nonexistent/file.yml") }
    end
    
    assert_match(/Error: Configuration file not found/, output)
  end

  def test_detect_providers_command
    # Mock environment variables
    original_env = ENV.to_h
    ENV["OPENAI_API_KEY"] = "test-openai-key"
    ENV["ANTHROPIC_API_KEY"] = "test-anthropic-key"

    output = capture_output { @cli.detect_providers }
    
    assert_match(/Detecting available providers/, output)
    assert_match(/openai: Available/, output)
    assert_match(/anthropic: Available/, output)
    
    # Restore environment
    ENV.clear
    original_env.each { |k, v| ENV[k] = v }
  end

  def test_detect_providers_with_missing_credentials
    # Clear relevant environment variables
    original_env = ENV.to_h
    ENV.delete("OPENAI_API_KEY")
    ENV.delete("ANTHROPIC_API_KEY")

    output = capture_output { @cli.detect_providers }
    
    assert_match(/Detecting available providers/, output)
    assert_match(/openai: Not configured/, output)
    assert_match(/anthropic: Not configured/, output)
    
    # Restore environment
    ENV.clear
    original_env.each { |k, v| ENV[k] = v }
  end

  def test_help_command
    output = capture_output { @cli.help }
    
    assert_match(/Commands:/, output)
    assert_match(/claude-swarm-multi-model detect-providers/, output)
    assert_match(/claude-swarm-multi-model help/, output)
    assert_match(/claude-swarm-multi-model list-providers/, output)
    assert_match(/claude-swarm-multi-model serve/, output)
    assert_match(/claude-swarm-multi-model validate-config/, output)
    assert_match(/claude-swarm-multi-model version/, output)
  end

  def test_help_for_specific_command
    output = capture_output { @cli.help("serve") }
    
    assert_match(/Usage:/, output)
    assert_match(/claude-swarm-multi-model serve/, output)
    assert_match(/Start the MCP server/, output)
  end

  def test_unknown_command
    # Thor handles unknown commands by showing help
    output = capture_output(:stderr) do
      # Simulate calling unknown command
      ClaudeSwarmMultiModel::CLI.start(["unknown-command"])
    end
    
    assert_match(/Could not find command "unknown-command"/, output)
  end

  def test_cli_error_handling
    # Test that CLI properly handles and reports errors
    ClaudeSwarmMultiModel::Mcp::Server.stub :new, ->(*args) { raise "Server error" } do
      output = capture_output(:stderr) do
        assert_raises(RuntimeError) { @cli.serve }
      end
    end
  end

  def test_cli_with_global_options
    skip "Global options implementation pending"
    
    # Test --debug flag
    @cli.options = { debug: true }
    
    output = capture_output { @cli.version }
    assert_match(/Debug mode enabled/, output)
  end

  private

  def capture_output(stream = :stdout)
    captured = StringIO.new
    
    case stream
    when :stdout
      $stdout = captured
    when :stderr
      $stderr = captured
    end
    
    yield
    
    captured.string
  ensure
    $stdout = @original_stdout
    $stderr = @original_stderr
  end
end