# frozen_string_literal: true

require "test_helper"

class TestProviderRegistry < Minitest::Test
  def setup
    @original_env = {}
    ClaudeSwarmMultiModel::ProviderRegistry::PROVIDERS.each do |provider, config|
      env_var = config[:env_var]
      @original_env[env_var] = ENV.fetch(env_var, nil) if env_var
    end
  end

  def teardown
    @original_env.each { |key, value| ENV[key] = value }
  end

  def test_list_providers_returns_all_providers
    providers = ClaudeSwarmMultiModel::ProviderRegistry.list_providers
    
    assert providers.is_a?(Hash)
    assert_includes providers.keys, "openai"
    assert_includes providers.keys, "gemini"
    assert_includes providers.keys, "groq"
    assert_includes providers.keys, "deepseek"
    assert_includes providers.keys, "together"
    assert_includes providers.keys, "local"
  end

  def test_provider_info_structure
    providers = ClaudeSwarmMultiModel::ProviderRegistry.list_providers
    
    providers.each do |key, info|
      assert info[:name], "Provider #{key} should have a name"
      assert info[:models].is_a?(Array), "Provider #{key} should have models array"
      assert !info[:models].empty?, "Provider #{key} should have at least one model"
    end
  end

  def test_supported_provider_check
    assert ClaudeSwarmMultiModel::ProviderRegistry.supported_provider?("openai")
    assert ClaudeSwarmMultiModel::ProviderRegistry.supported_provider?("gemini")
    assert ClaudeSwarmMultiModel::ProviderRegistry.supported_provider?("local")
    refute ClaudeSwarmMultiModel::ProviderRegistry.supported_provider?("unsupported")
  end

  def test_supported_model_check
    # Test valid provider/model combinations
    assert ClaudeSwarmMultiModel::ProviderRegistry.supported_model?("openai", "gpt-4o")
    assert ClaudeSwarmMultiModel::ProviderRegistry.supported_model?("openai", "gpt-4o-mini")
    assert ClaudeSwarmMultiModel::ProviderRegistry.supported_model?("gemini", "gemini-pro")
    assert ClaudeSwarmMultiModel::ProviderRegistry.supported_model?("groq", "llama-3.3-70b-versatile")
    
    # Local provider should accept any model
    assert ClaudeSwarmMultiModel::ProviderRegistry.supported_model?("local", "any-model")
    assert ClaudeSwarmMultiModel::ProviderRegistry.supported_model?("local", "custom-llm")
    
    # Test invalid combinations
    refute ClaudeSwarmMultiModel::ProviderRegistry.supported_model?("openai", "claude-3")
    refute ClaudeSwarmMultiModel::ProviderRegistry.supported_model?("gemini", "gpt-4")
    refute ClaudeSwarmMultiModel::ProviderRegistry.supported_model?("unsupported", "any-model")
  end

  def test_get_provider_config
    config = ClaudeSwarmMultiModel::ProviderRegistry.get_provider_config("openai")
    
    assert_equal "OpenAI", config[:name]
    assert_equal "OPENAI_API_KEY", config[:env_var]
    assert_includes config[:models], "gpt-4o"
    assert_includes config[:models], "gpt-4o-mini"
    
    # Test non-existent provider
    assert_nil ClaudeSwarmMultiModel::ProviderRegistry.get_provider_config("nonexistent")
  end

  def test_detect_available_providers_with_env_vars
    # Set some API keys
    ENV["OPENAI_API_KEY"] = "test-openai-key"
    ENV["GEMINI_API_KEY"] = "test-gemini-key"
    ENV.delete("GROQ_API_KEY")
    ENV["LOCAL_LLM_BASE_URL"] = "http://localhost:11434"
    
    available = ClaudeSwarmMultiModel::ProviderRegistry.detect_available_providers
    
    assert_includes available, "openai"
    assert_includes available, "gemini"
    assert_includes available, "local"
    refute_includes available, "groq"
  end

  def test_detect_available_providers_without_env_vars
    # Clear all provider environment variables
    ClaudeSwarmMultiModel::ProviderRegistry::PROVIDERS.each do |_, config|
      ENV.delete(config[:env_var]) if config[:env_var]
    end
    
    available = ClaudeSwarmMultiModel::ProviderRegistry.detect_available_providers
    
    # Only local should be available (no env var required)
    assert_equal ["local"], available
  end

  def test_provider_available_check
    ENV["OPENAI_API_KEY"] = "test-key"
    ENV.delete("GROQ_API_KEY")
    
    assert ClaudeSwarmMultiModel::ProviderRegistry.provider_available?("openai")
    refute ClaudeSwarmMultiModel::ProviderRegistry.provider_available?("groq")
    assert ClaudeSwarmMultiModel::ProviderRegistry.provider_available?("local")
    refute ClaudeSwarmMultiModel::ProviderRegistry.provider_available?("nonexistent")
  end

  def test_get_env_var_for_provider
    assert_equal "OPENAI_API_KEY", ClaudeSwarmMultiModel::ProviderRegistry.get_env_var_for_provider("openai")
    assert_equal "GEMINI_API_KEY", ClaudeSwarmMultiModel::ProviderRegistry.get_env_var_for_provider("gemini")
    assert_equal "LOCAL_LLM_BASE_URL", ClaudeSwarmMultiModel::ProviderRegistry.get_env_var_for_provider("local")
    assert_nil ClaudeSwarmMultiModel::ProviderRegistry.get_env_var_for_provider("nonexistent")
  end

  def test_providers_constant_structure
    ClaudeSwarmMultiModel::ProviderRegistry::PROVIDERS.each do |key, config|
      assert config.is_a?(Hash), "Provider #{key} config should be a hash"
      assert config[:name], "Provider #{key} should have a name"
      assert config[:models].is_a?(Array), "Provider #{key} should have models array"
      
      # All except local should have env_var
      if key != "local"
        assert config[:env_var], "Provider #{key} should have env_var"
        assert config[:env_var].match?(/^[A-Z_]+$/), "Provider #{key} env_var should be uppercase with underscores"
      end
    end
  end

  def test_model_list_completeness
    providers = ClaudeSwarmMultiModel::ProviderRegistry::PROVIDERS
    
    # Verify OpenAI models
    openai_models = providers["openai"][:models]
    assert_includes openai_models, "gpt-4o"
    assert_includes openai_models, "gpt-4o-mini"
    assert_includes openai_models, "gpt-4-turbo"
    assert_includes openai_models, "gpt-3.5-turbo"
    
    # Verify Gemini models
    gemini_models = providers["gemini"][:models]
    assert_includes gemini_models, "gemini-pro"
    assert_includes gemini_models, "gemini-1.5-pro"
    assert_includes gemini_models, "gemini-1.5-flash"
    
    # Verify Together AI has some models
    together_models = providers["together"][:models]
    assert together_models.size > 5, "Together AI should have multiple models"
  end

  def test_thread_safety
    results = Concurrent::Array.new
    threads = []
    
    # Simulate concurrent access to provider registry
    10.times do |i|
      threads << Thread.new do
        ENV["OPENAI_API_KEY"] = "key-#{i}" if i.even?
        
        available = ClaudeSwarmMultiModel::ProviderRegistry.detect_available_providers
        supported = ClaudeSwarmMultiModel::ProviderRegistry.supported_provider?("openai")
        
        results << { available: available, supported: supported }
      end
    end
    
    threads.each(&:join)
    
    assert_equal 10, results.size
    results.each do |result|
      assert result[:available].is_a?(Array)
      assert [true, false].include?(result[:supported])
    end
  end
end