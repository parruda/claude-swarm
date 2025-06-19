# frozen_string_literal: true

require_relative "test_helper"
require "claude_swarm_multi_model/config_validator"

class TestConfigValidator < Minitest::Test
  def setup
    # Save original ENV values
    @original_env = {}
    %w[OPENAI_API_KEY GEMINI_API_KEY GROQ_API_KEY DEEPSEEK_API_KEY TOGETHER_API_KEY LOCAL_LLM_BASE_URL].each do |key|
      @original_env[key] = ENV.fetch(key, nil)
    end
  end

  def teardown
    # Restore original ENV values
    @original_env.each { |key, value| ENV[key] = value }
  end

  def test_validate_instance_with_anthropic_provider
    # Should not raise for default Anthropic provider
    ClaudeSwarmMultiModel::ConfigValidator.validate_instance("test", {
                                                               "model" => "claude-3-5-sonnet-20241022"
                                                             })
  end

  def test_validate_instance_with_openai_provider
    instance_config = {
      "provider" => "openai",
      "model" => "gpt-4o"
    }

    ClaudeSwarmMultiModel::ConfigValidator.validate_instance("test", instance_config)

    # Should add api_key_env to config
    assert_equal "OPENAI_API_KEY", instance_config["api_key_env"]
  end

  def test_validate_instance_with_unsupported_provider
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarmMultiModel::ConfigValidator.validate_instance("test", {
                                                                 "provider" => "unsupported_provider",
                                                                 "model" => "some-model"
                                                               })
    end

    assert_match(/unsupported provider/, error.message)
  end

  def test_validate_instance_with_unsupported_model
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarmMultiModel::ConfigValidator.validate_instance("test", {
                                                                 "provider" => "openai",
                                                                 "model" => "unsupported-model"
                                                               })
    end

    assert_match(/unsupported model/, error.message)
  end

  def test_validate_instance_with_local_provider
    instance_config = {
      "provider" => "local",
      "model" => "any-local-model"
    }

    # Should not raise for any model with local provider
    ClaudeSwarmMultiModel::ConfigValidator.validate_instance("test", instance_config)

    # Should add base_url_env to config
    assert_equal "LOCAL_LLM_BASE_URL", instance_config["base_url_env"]
  end

  def test_process_config_validates_api_keys
    # Mock a configuration object
    config = MockConfiguration.new({
                                     "main" => { provider: "anthropic" },
                                     "assistant" => { provider: "openai" }
                                   })

    # Should raise error when API key is missing
    ENV["OPENAI_API_KEY"] = nil
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarmMultiModel::ConfigValidator.process_config(config)
    end

    assert_match(/OPENAI_API_KEY/, error.message)
  end

  def test_process_config_with_all_api_keys_set
    # Mock a configuration object
    config = MockConfiguration.new({
                                     "main" => { provider: "anthropic" },
                                     "assistant" => { provider: "openai" }
                                   })

    # Set required API key
    ENV["OPENAI_API_KEY"] = "test-key"

    # Should not raise when API key is present
    # Note: This will fail if ruby_llm is not installed, which is expected
    begin
      ClaudeSwarmMultiModel::ConfigValidator.process_config(config)
    rescue ClaudeSwarm::Error => e
      assert_match(/ruby_llm gem is required/, e.message)
    end
  end

  # Mock configuration class for testing
  class MockConfiguration
    attr_reader :instances

    def initialize(instances_hash)
      @instances = instances_hash.transform_values { |v| v }
    end

    def instance_names
      @instances.keys
    end
  end
end
