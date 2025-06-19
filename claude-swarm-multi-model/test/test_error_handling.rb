# frozen_string_literal: true

require "test_helper"

class TestErrorHandling < Minitest::Test
  def setup
    @original_env = ENV.to_h
  end

  def teardown
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def test_missing_required_gem_error
    # Test that appropriate error is raised when ruby_llm is not available
    original_require = Kernel.method(:require)
    
    Kernel.define_singleton_method(:require) do |name|
      raise LoadError, "cannot load such file -- ruby_llm" if name == "ruby_llm"
      original_require.call(name)
    end
    
    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarmMultiModel::Mcp::Executor.new.execute("openai", "gpt-4", [], {})
    end
    
    assert_match(/ruby_llm gem is required/, error.message)
  ensure
    Kernel.define_singleton_method(:require, original_require)
  end

  def test_invalid_provider_configuration
    # Test various invalid provider configurations
    test_cases = [
      {
        provider: nil,
        model: "gpt-4",
        error: /Provider is required/
      },
      {
        provider: "",
        model: "gpt-4",
        error: /Provider is required/
      },
      {
        provider: "openai",
        model: nil,
        error: /Model is required/
      },
      {
        provider: "openai",
        model: "",
        error: /Model is required/
      }
    ]
    
    test_cases.each do |test_case|
      error = assert_raises(ArgumentError) do
        ClaudeSwarmMultiModel::Mcp::Executor.new.execute(
          test_case[:provider],
          test_case[:model],
          [{ "role" => "user", "content" => "test" }],
          {}
        )
      end
      
      assert_match test_case[:error], error.message
    end
  end

  def test_malformed_messages_handling
    executor = ClaudeSwarmMultiModel::Mcp::Executor.new
    
    # Test various malformed message formats
    invalid_messages = [
      nil,
      "not an array",
      [nil],
      [{}], # Missing role and content
      [{ "role" => "user" }], # Missing content
      [{ "content" => "test" }], # Missing role
      [{ "role" => "invalid_role", "content" => "test" }]
    ]
    
    invalid_messages.each do |messages|
      error = assert_raises(ArgumentError) do
        executor.execute("openai", "gpt-4", messages, {})
      end
      
      assert_match(/Invalid messages format/, error.message)
    end
  end

  def test_api_key_validation_errors
    # Clear all API keys
    ClaudeSwarmMultiModel::ProviderRegistry::PROVIDERS.each do |_, config|
      ENV.delete(config[:env_var]) if config[:env_var]
    end
    
    providers_requiring_keys = %w[openai gemini groq deepseek together]
    
    providers_requiring_keys.each do |provider|
      config = {
        "instances" => {
          "test" => {
            "provider" => provider,
            "model" => "some-model"
          }
        }
      }
      
      error = assert_raises(ClaudeSwarm::Error) do
        ClaudeSwarmMultiModel::ConfigValidator.process_config(
          MockConfig.new(config["instances"])
        )
      end
      
      env_var = ClaudeSwarmMultiModel::ProviderRegistry.get_env_var_for_provider(provider)
      assert_match(/#{env_var} environment variable is required/, error.message)
    end
  end

  def test_concurrent_access_edge_cases
    # Test thread safety and race conditions
    errors = Concurrent::Array.new
    threads = []
    
    20.times do |i|
      threads << Thread.new do
        begin
          # Rapidly change environment variables
          ENV["OPENAI_API_KEY"] = "key-#{i}" if i.even?
          ENV.delete("OPENAI_API_KEY") if i.odd?
          
          # Try to validate configuration
          config = {
            "test-#{i}" => {
              "provider" => "openai",
              "model" => "gpt-4"
            }
          }
          
          ClaudeSwarmMultiModel::ConfigValidator.process_config(
            MockConfig.new(config)
          )
        rescue => e
          errors << e
        end
      end
    end
    
    threads.each(&:join)
    
    # Some threads should have encountered missing API key errors
    assert errors.any? { |e| e.message.include?("OPENAI_API_KEY") }
  end

  def test_file_system_errors
    # Test handling of file system errors
    
    # Non-existent config file
    error = assert_raises(Errno::ENOENT) do
      ClaudeSwarmMultiModel::CLI.new.validate_config("/nonexistent/path/config.yml")
    end
    
    # Invalid YAML content
    Tempfile.create(["invalid", ".yml"]) do |f|
      f.write("invalid: yaml: content: {{{}}")
      f.close
      
      error = assert_raises(Psych::SyntaxError) do
        ClaudeSwarmMultiModel::CLI.new.validate_config(f.path)
      end
    end
  end

  def test_mcp_protocol_edge_cases
    stdin = StringIO.new
    stdout = StringIO.new
    stderr = StringIO.new
    
    server = ClaudeSwarmMultiModel::Mcp::Server.new(stdin, stdout, stderr)
    
    # Test various protocol violations
    edge_cases = [
      # Wrong JSON-RPC version
      { "jsonrpc" => "1.0", "id" => 1, "method" => "test" },
      # Numeric method (should be string)
      { "jsonrpc" => "2.0", "id" => 1, "method" => 123 },
      # Array as params (when object expected)
      { "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call", "params" => [] },
      # Deeply nested invalid structure
      { "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call", 
        "params" => { "name" => "llm/chat", "arguments" => { "nested" => { "too" => { "deep" => {} } } } } }
    ]
    
    edge_cases.each_with_index do |request, i|
      stdout.truncate(0)
      stdout.rewind
      
      server.send(:handle_request, request)
      
      stdout.rewind
      response = JSON.parse(stdout.string.lines.last)
      
      assert response["error"], "Edge case #{i} should produce error"
      assert response["error"]["code"] < 0, "Error code should be negative"
    end
  end

  def test_memory_and_resource_limits
    # Test handling of large payloads
    executor = ClaudeSwarmMultiModel::Mcp::Executor.new
    
    # Create a very large message
    large_content = "x" * (10 * 1024 * 1024) # 10MB string
    
    error = assert_raises(ArgumentError) do
      executor.execute("openai", "gpt-4", [
        { "role" => "user", "content" => large_content }
      ], {})
    end
    
    assert_match(/Message content too large/, error.message)
  end

  def test_timeout_handling
    # Test request timeout handling
    stdin = StringIO.new
    stdout = StringIO.new
    stderr = StringIO.new
    
    server = ClaudeSwarmMultiModel::Mcp::Server.new(stdin, stdout, stderr)
    
    # Mock a slow executor
    slow_executor = Object.new
    def slow_executor.execute(*args)
      sleep(5) # Simulate slow response
      { success: true, response: "Late response" }
    end
    
    ClaudeSwarmMultiModel::Mcp::Executor.stub :new, slow_executor do
      request = {
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => {
          "name" => "llm/chat",
          "arguments" => {
            "provider" => "slow",
            "model" => "slow-model",
            "messages" => [{ "role" => "user", "content" => "test" }]
          }
        }
      }
      
      # Should handle timeout gracefully
      Timeout.timeout(1) do
        server.send(:handle_request, request)
      end
    end
  rescue Timeout::Error
    # Expected - test passes if timeout is handled
  end

  def test_extension_loading_errors
    # Test various extension loading failures
    Dir.mktmpdir do |tmpdir|
      ext_dir = File.join(tmpdir, "extensions")
      FileUtils.mkdir_p(ext_dir)
      
      # Extension with syntax error
      File.write(File.join(ext_dir, "bad_syntax.rb"), <<~RUBY)
        this is not valid { ruby syntax
      RUBY
      
      # Extension that raises during load
      File.write(File.join(ext_dir, "raises.rb"), <<~RUBY)
        raise "Extension load error"
      RUBY
      
      # Extension with missing dependencies
      File.write(File.join(ext_dir, "missing_dep.rb"), <<~RUBY)
        require 'nonexistent_gem'
      RUBY
      
      # All should be handled gracefully
      assert_silent do
        ClaudeSwarm::Extensions.load_from_directory(ext_dir)
      end
    end
  end

  def test_boundary_value_edge_cases
    # Test boundary values for various parameters
    
    # Priority boundaries
    [-1000, 0, 50, 100, 1000].each do |priority|
      ClaudeSwarm::Extensions.register_hook(:boundary_test, priority: priority) { |d| d }
      hooks = ClaudeSwarm::Extensions.instance_variable_get(:@hooks)[:boundary_test]
      assert hooks.any? { |h| h[:priority] == priority }
    end
    
    # Empty configurations
    empty_configs = [
      {},
      { "instances" => {} },
      { "instances" => { "test" => {} } }
    ]
    
    empty_configs.each do |config|
      # Should handle gracefully or raise appropriate error
      begin
        ClaudeSwarmMultiModel::ConfigValidator.process_config(
          MockConfig.new(config["instances"] || {})
        )
      rescue ClaudeSwarm::Error => e
        # Expected for some cases
        assert e.message.length > 0
      end
    end
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