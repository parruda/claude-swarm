# frozen_string_literal: true

require "test_helper"

class TestExtension < Minitest::Test
  def setup
    # Clear any existing extensions/hooks
    if defined?(ClaudeSwarm::Extensions)
      ClaudeSwarm::Extensions.instance_variable_set(:@extensions, {})
      ClaudeSwarm::Extensions.instance_variable_set(:@hooks, {})
    end
    
    # Track hook executions
    @hook_executions = []
  end

  def teardown
    if defined?(ClaudeSwarm::Extensions)
      ClaudeSwarm::Extensions.instance_variable_set(:@extensions, {})
      ClaudeSwarm::Extensions.instance_variable_set(:@hooks, {})
    end
  end

  def test_extension_registers_itself
    # Load the extension
    require "claude_swarm_multi_model/extension"
    
    extensions = ClaudeSwarm::Extensions.list_extensions
    assert_includes extensions.keys, "claude-swarm-multi-model"
    
    ext_info = extensions["claude-swarm-multi-model"]
    assert_equal ClaudeSwarmMultiModel::VERSION, ext_info[:version]
    assert_equal "Multi-model LLM support for Claude Swarm", ext_info[:description]
    assert_equal "github.com/parruda/claude-swarm", ext_info[:author]
  end

  def test_before_config_load_hook
    # Mock configuration
    config = {
      "instances" => {
        "main" => {
          "provider" => "openai",
          "model" => "gpt-4o"
        },
        "assistant" => {
          "provider" => "gemini",
          "model" => "gemini-pro"
        }
      }
    }
    
    # Load extension to register hooks
    require "claude_swarm_multi_model/extension"
    
    # Execute hook
    result = ClaudeSwarm::Extensions.execute_hook(:before_config_load, config)
    
    # Should pass through config unchanged (validation happens elsewhere)
    assert_equal config, result
  end

  def test_before_instance_launch_hook
    # Load extension
    require "claude_swarm_multi_model/extension"
    
    instance_config = {
      "name" => "test",
      "provider" => "openai",
      "model" => "gpt-4o",
      "api_key_env" => "OPENAI_API_KEY"
    }
    
    # Mock environment
    ENV["OPENAI_API_KEY"] = "test-key"
    
    # Execute hook
    result = ClaudeSwarm::Extensions.execute_hook(:before_instance_launch, instance_config.dup)
    
    # Should add multi-model MCP server
    assert result["mcp_servers"]
    assert result["mcp_servers"]["multi-model"]
    
    mcp_config = result["mcp_servers"]["multi-model"]
    assert_equal "stdio", mcp_config["transport"]["type"]
    assert_equal "claude-swarm-multi-model", mcp_config["transport"]["command"]["command"]
    assert_equal ["serve"], mcp_config["transport"]["command"]["args"]
  end

  def test_after_mcp_generation_hook
    require "claude_swarm_multi_model/extension"
    
    # Mock MCP configuration
    mcp_config = {
      "mcpServers" => {
        "existing" => {
          "transport" => {
            "type" => "stdio",
            "command" => {
              "command" => "some-command"
            }
          }
        }
      }
    }
    
    instance_config = {
      "multi_model_enabled" => true
    }
    
    # Execute hook
    result = ClaudeSwarm::Extensions.execute_hook(:after_mcp_generation, {
      mcp_config: mcp_config,
      instance_config: instance_config
    })
    
    # Should preserve existing servers
    assert result[:mcp_config]["mcpServers"]["existing"]
    
    # Could add multi-model server if needed
    # (implementation depends on specific requirements)
  end

  def test_hook_integration_with_config_validation
    require "claude_swarm_multi_model/extension"
    
    # Create a config that needs validation
    config = {
      "instances" => {
        "test" => {
          "provider" => "unsupported",
          "model" => "invalid-model"
        }
      }
    }
    
    # The before_config_load hook should trigger validation
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::Extensions.execute_hook(:before_config_load, config)
    end
    
    assert_match(/unsupported provider/, error.message)
  end

  def test_hook_priorities
    require "claude_swarm_multi_model/extension"
    
    # Register additional test hooks to verify ordering
    ClaudeSwarm::Extensions.register_hook(:before_instance_launch, priority: 10) do |config|
      @hook_executions << "priority_10"
      config
    end
    
    ClaudeSwarm::Extensions.register_hook(:before_instance_launch, priority: 90) do |config|
      @hook_executions << "priority_90"
      config
    end
    
    # Execute hooks
    ClaudeSwarm::Extensions.execute_hook(:before_instance_launch, {})
    
    # Multi-model hook has priority 60, so order should be: 10, 60, 90
    assert_equal "priority_10", @hook_executions.first
    assert_equal "priority_90", @hook_executions.last
  end

  def test_extension_error_handling
    require "claude_swarm_multi_model/extension"
    
    # Register a hook that raises an error
    ClaudeSwarm::Extensions.register_hook(:before_config_load, priority: 1) do |config|
      raise "Test error"
    end
    
    # The multi-model validation should still run despite the error
    config = {
      "instances" => {
        "test" => {
          "provider" => "openai",
          "model" => "gpt-4o"
        }
      }
    }
    
    # Should not raise the test error, but continue to validation
    result = ClaudeSwarm::Extensions.execute_hook(:before_config_load, config)
    assert result # Hook chain continues despite error
  end

  def test_extension_with_environment_variables
    require "claude_swarm_multi_model/extension"
    
    # Test with different environment setups
    original_env = ENV.to_h
    
    # Clear environment
    ENV.delete("OPENAI_API_KEY")
    ENV.delete("CLAUDE_SWARM_MULTI_MODEL_ENABLED")
    
    instance_config = {
      "name" => "test",
      "provider" => "openai",
      "model" => "gpt-4o"
    }
    
    # Without API key, validation should fail
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarmMultiModel::ConfigValidator.process_config(
        MockConfig.new({ "test" => instance_config })
      )
    end
    
    assert_match(/OPENAI_API_KEY/, error.message)
    
    # Restore environment
    ENV.clear
    original_env.each { |k, v| ENV[k] = v }
  end

  def test_extension_metadata
    require "claude_swarm_multi_model/extension"
    
    extensions = ClaudeSwarm::Extensions.list_extensions
    metadata = extensions["claude-swarm-multi-model"]
    
    # Verify all metadata fields
    assert metadata[:version]
    assert metadata[:description]
    assert metadata[:author]
    assert metadata[:hooks]
    
    # Verify hooks are registered
    assert_includes metadata[:hooks], :before_config_load
    assert_includes metadata[:hooks], :before_instance_launch
    assert_includes metadata[:hooks], :after_mcp_generation
  end

  private

  class MockConfig
    attr_reader :instances
    
    def initialize(instances)
      @instances = instances
    end
    
    def instance_names
      @instances.keys
    end
  end
end