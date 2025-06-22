# Multi-Provider Support Implementation Plan

## Overview

Enable Claude Swarm to orchestrate AI agents using any model/provider supported by the ruby_llm gem (OpenAI, Google Gemini, Cohere, etc.), extending beyond Claude-only swarms.

## Core Design Principle

Users who only need Claude/Anthropic models should NOT need to install additional dependencies. Multi-provider support is opt-in via the `claude-swarm-providers` extension gem.

## Architecture: Plugin Pattern with Detection

### 1. Core Gem Structure

The `claude-swarm` gem will:
- Contain provider abstraction code but no provider implementations
- Detect if `ruby_llm` is available and load provider code conditionally
- Keep all existing functionality working without changes

### 2. Extension Gem Structure

The `claude-swarm-providers` gem will:
- Be a simple dependency installer (metagem pattern)
- Add `ruby_llm` and `ruby_llm-mcp` as dependencies
- No code - just pulls in required gems

### 3. Detection Mechanism

```ruby
# lib/claude_swarm.rb
module ClaudeSwarm
  # ... existing requires
  
  # Conditionally load provider support if gem is available
  begin
    require 'ruby_llm'
    require 'ruby_llm/mcp'
    require 'claude_swarm/providers/llm_executor'
  rescue LoadError
    # Provider support not available
  end
end
```

## Implementation Components

### 1. Base Executor Abstraction

```ruby
# lib/claude_swarm/base_executor.rb
module ClaudeSwarm
  class BaseExecutor
    attr_reader :session_id, :last_response, :working_directory, :logger, :session_path
    
    def initialize(working_directory:, instance_name:, instance_id:, 
                   calling_instance:, calling_instance_id:, **options)
      @working_directory = working_directory
      @instance_name = instance_name
      @instance_id = instance_id
      @calling_instance = calling_instance
      @calling_instance_id = calling_instance_id
      @session_id = nil
      @last_response = nil
      
      setup_logging
    end
    
    def execute(prompt, options = {})
      raise NotImplementedError, "Subclasses must implement execute"
    end
    
    def reset_session
      @session_id = nil
      @last_response = nil
    end
    
    def has_session?
      !@session_id.nil?
    end
    
    private
    
    def setup_logging
      @session_path = SessionPath.from_env
      SessionPath.ensure_directory(@session_path)
      
      log_path = File.join(@session_path, "session.log")
      @logger = Logger.new(log_path)
      @logger.level = Logger::INFO
      
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S.%L")}] [#{severity}] #{msg}\n"
      end
    end
    
    def append_to_session_json(entry)
      json_path = File.join(@session_path, "session.log.json")
      
      File.open(json_path, File::WRONLY | File::APPEND | File::CREAT) do |file|
        file.flock(File::LOCK_EX)
        file.puts(entry.to_json)
        file.flock(File::LOCK_UN)
      end
    end
  end
end
```

### 2. Executor Factory

```ruby
# lib/claude_swarm/executor_factory.rb
module ClaudeSwarm
  class ExecutorFactory
    def self.create(instance_config, calling_instance:, calling_instance_id:)
      provider = instance_config[:provider] || 'anthropic'
      
      common_options = {
        working_directory: instance_config[:directory],
        instance_name: instance_config[:name],
        instance_id: instance_config[:instance_id],
        calling_instance: calling_instance,
        calling_instance_id: calling_instance_id,
        additional_directories: instance_config[:directories][1..] || [],
        mcp_config: instance_config[:mcp_config_path],
        vibe: instance_config[:vibe]
      }
      
      if provider == 'anthropic'
        ClaudeCodeExecutor.new(
          model: instance_config[:model],
          claude_session_id: instance_config[:claude_session_id],
          **common_options
        )
      else
        require_provider_support!
        Providers::LlmExecutor.new(
          provider: provider,
          model: instance_config[:model],
          api_key_env: instance_config[:api_key_env],
          api_base_env: instance_config[:api_base_env],
          assume_model_exists: instance_config[:assume_model_exists],
          **common_options
        )
      end
    end
    
    private
    
    def self.require_provider_support!
      unless defined?(::ClaudeSwarm::Providers::LlmExecutor)
        raise "Install claude-swarm-providers gem to use non-Anthropic models"
      end
    end
  end
end
```

### 3. Configuration Schema Updates

```yaml
version: 1
swarm:
  name: "Multi-Model Dev Team"
  main: lead
  instances:
    # Claude/Anthropic instance (default)
    lead:
      description: "Claude Opus lead coordinating the team"
      directory: .
      model: opus
      # provider: anthropic  # Optional, defaults to anthropic
      connections: [gemini_critic, gpt_analyst]
      
    # Google Gemini instance
    gemini_critic:
      provider: google
      model: gemini-2.0-flash
      api_key_env: GEMINI_API_KEY  # Optional: custom env var
      description: "2M context window code reviewer"
      
    # OpenAI instance
    gpt_analyst:
      provider: openai
      model: gpt-4-turbo
      description: "GPT-4 for complex analysis"
      
    # Custom OpenAI-compatible endpoint (Azure, Ollama, etc.)
    azure_gpt:
      provider: openai
      model: my-gpt4-deployment
      api_base_env: AZURE_OPENAI_BASE  # Custom base URL env var
      api_key_env: AZURE_OPENAI_KEY    # Custom API key env var
      assume_model_exists: true         # Skip model validation
```

### 2. CLI Updates

```ruby
# lib/claude_swarm/cli.rb - add to mcp_serve method options
method_option :provider, type: :string, default: "anthropic",
                        desc: "LLM provider (anthropic, openai, google, etc.)"
method_option :api_key_env, type: :string,
                           desc: "Environment variable name for API key"
method_option :api_base_env, type: :string,
                            desc: "Environment variable name for custom API base URL"
method_option :assume_model_exists, type: :boolean, default: false,
                                   desc: "Skip model validation (for custom deployments)"
```

### 5. Update ClaudeMcpServer to Use Factory

```ruby
# lib/claude_swarm/claude_mcp_server.rb
class ClaudeMcpServer
  def initialize(instance_config, calling_instance:, calling_instance_id: nil)
    @instance_config = instance_config
    @calling_instance = calling_instance
    @calling_instance_id = calling_instance_id
    
    # Use factory to create appropriate executor
    @executor = ExecutorFactory.create(
      instance_config,
      calling_instance: calling_instance,
      calling_instance_id: calling_instance_id
    )
    
    # Set class variables so tools can access them
    self.class.executor = @executor
    self.class.instance_config = @instance_config
    self.class.logger = @executor.logger
    self.class.session_path = @executor.session_path
    self.class.calling_instance = @calling_instance
    self.class.calling_instance_id = @calling_instance_id
  end
  
  # Rest of the class remains unchanged
end
```

### 6. Create LlmExecutor

```ruby
# lib/claude_swarm/providers/llm_executor.rb
module ClaudeSwarm
  module Providers
    class LlmExecutor < BaseExecutor
      
      def initialize(provider:, model:, api_key_env: nil, api_base_env: nil, 
                     assume_model_exists: false, **common_options)
        super(**common_options)
        
        @provider = provider
        @model = model
        @assume_model_exists = assume_model_exists
        
        # Create a context for this instance to avoid polluting global config
        @llm_context = RubyLlm.context do |config|
          # Set API key
          key_env = api_key_env || "#{provider.upcase}_API_KEY"
          api_key = ENV[key_env]
          raise "Missing API key in #{key_env}" unless api_key
          
          case provider
          when 'openai'
            config.openai_api_key = api_key
            
            # Set custom base URL if provided
            if api_base_env && ENV[api_base_env]
              config.openai_api_base = ENV[api_base_env]
            elsif ENV['OPENAI_API_BASE']
              config.openai_api_base = ENV['OPENAI_API_BASE']
            end
          when 'anthropic'
            config.anthropic_api_key = api_key
          when 'google'
            config.gemini_api_key = api_key
          # ... other providers
          end
        end
      end
      
      def execute(prompt, options = {})
        start_time = Time.now
        
        # Log the request
        log_request(prompt)
        
        # Check provider capabilities
        tools = nil
        if provider_supports_tools?(@provider)
          tools = map_tools_for_provider(options[:allowed_tools])
        end
        
        # Execute with RubyLLM
        messages = build_messages(prompt, options)
        response = @llm_context.chat(
          messages: messages,
          model: @model,
          provider: @provider.to_sym,
          assume_model_exists: @assume_model_exists,
          tools: tools
        ) do |chunk|
          # Log streaming chunks if needed
          log_streaming_chunk(chunk) if chunk.content || chunk.tool_calls
        end
        
        # Format and log response
        duration_ms = ((Time.now - start_time) * 1000).round
        result = format_as_claude_response(response, duration_ms)
        
        @last_response = result
        @session_id ||= generate_session_id  # Generate if first request
        
        result
      end
      
      private
      
      def log_request(prompt)
        # Log to text log
        @logger.info("#{@calling_instance} -> #{@instance_name}: \n---\n#{prompt}\n---")
        
        # Log to JSON
        log_event({
          type: "request",
          prompt: prompt,
          model: @model,
          provider_name: @provider
        })
      end
      
      def log_event(event)
        entry = {
          instance: @instance_name,
          instance_id: @instance_id,
          calling_instance: @calling_instance,
          calling_instance_id: @calling_instance_id,
          timestamp: Time.now.iso8601,
          provider: "ruby_llm",  # Differentiate from "claude-code"
          event: event
        }
        
        append_to_session_json(entry)
      end
      
      def format_as_claude_response(response, duration_ms)
        # Use ResponseNormalizer to format
        ResponseNormalizer.normalize(
          provider: @provider,
          response: response,
          duration_ms: duration_ms,
          session_id: @session_id
        )
      end
      
      def build_messages(prompt, options)
        # Convert prompt into message format
        messages = []
        
        # Add system prompt if provided
        if options[:system_prompt]
          messages << {role: 'system', content: options[:system_prompt]}
        end
        
        # Add user prompt
        messages << {role: 'user', content: prompt}
        
        messages
      end
      
      def provider_supports_tools?(provider)
        # Check provider capabilities
        case provider
        when 'openai', 'anthropic'
          true
        when 'google'
          false  # Gemini doesn't support tools via RubyLLM yet
        else
          false
        end
      end
      
      def map_tools_for_provider(allowed_tools)
        return nil if allowed_tools.nil? || allowed_tools.empty?
        
        # Map Claude tool names to provider-specific format
        # This would need actual implementation based on RubyLLM's tool format
        allowed_tools
      end
      
      def calculate_cost(response)
        # Provider-specific cost calculation
        # This would need actual pricing data
        input_cost = response.input_tokens * 0.00001
        output_cost = response.output_tokens * 0.00003
        (input_cost + output_cost).round(5)
      end
      
      def generate_session_id
        "llm-#{@provider}-#{Time.now.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
      end
    end
  end
end
```

### 7. Response Normalizer

```ruby
# lib/claude_swarm/providers/response_normalizer.rb
module ClaudeSwarm
  module Providers
    class ResponseNormalizer
      def self.normalize(provider:, response:, duration_ms:, session_id:)
        {
          "type" => "result",
          "result" => response.content,
          "duration_ms" => duration_ms,
          "total_cost" => calculate_provider_cost(provider, response),
          "session_id" => session_id,
          "usage" => {
            "input_tokens" => response.input_tokens || 0,
            "output_tokens" => response.output_tokens || 0
          }
        }
      end
      
      private
      
      def self.calculate_provider_cost(provider, response)
        # Provider-specific pricing
        case provider
        when 'openai'
          input_cost = (response.input_tokens || 0) * 0.00001
          output_cost = (response.output_tokens || 0) * 0.00003
        when 'google'
          input_cost = (response.input_tokens || 0) * 0.000005
          output_cost = (response.output_tokens || 0) * 0.000015
        else
          input_cost = output_cost = 0
        end
        
        (input_cost + output_cost).round(5)
      end
    end
  end
end
```

### 8. Provider Capabilities Registry

```ruby
# lib/claude_swarm/providers/capabilities.rb
module ClaudeSwarm
  module Providers
    CAPABILITIES = {
      'anthropic' => {
        supports_streaming: true,
        supports_tools: true,
        supports_system_prompt: true,
        max_context: 200_000,
        tool_format: :xml
      },
      'openai' => {
        supports_streaming: true,
        supports_tools: true,
        supports_system_prompt: true,
        max_context: 128_000,
        tool_format: :json,
        supports_custom_base: true
      },
      'google' => {
        supports_streaming: true,
        supports_tools: false,  # Not via RubyLLM yet
        supports_system_prompt: true,
        max_context: 2_000_000,
        tool_format: nil
      },
      'cohere' => {
        supports_streaming: true,
        supports_tools: true,
        supports_system_prompt: true,
        max_context: 128_000,
        tool_format: :json
      }
    }.freeze
    
    def self.supports?(provider, capability)
      CAPABILITIES.dig(provider, capability) || false
    end
  end
end
```

### 9. Update McpGenerator

```ruby
# lib/claude_swarm/mcp_generator.rb
def build_mcp_server_config(instance_name, instance_config)
  args = [
    "mcp-serve",
    "--name", instance_name,
    "--directory", instance_config[:directory],
    # ... existing args
  ]
  
  # Add provider if specified (defaults to anthropic)
  provider = instance_config[:provider] || 'anthropic'
  args += ["--provider", provider]
  
  # Add custom env vars if specified
  args += ["--api-key-env", instance_config[:api_key_env]] if instance_config[:api_key_env]
  args += ["--api-base-env", instance_config[:api_base_env]] if instance_config[:api_base_env]
  args += ["--assume-model-exists"] if instance_config[:assume_model_exists]
  
  {
    "command" => "claude-swarm",
    "args" => args,
    "type" => "stdio"
  }
end
```

### 10. Extension Gem

```ruby
# claude-swarm-providers/claude-swarm-providers.gemspec
Gem::Specification.new do |spec|
  spec.name = "claude-swarm-providers"
  spec.version = "0.1.0"
  spec.summary = "Multi-provider support for Claude Swarm"
  spec.description = "Adds support for OpenAI, Google Gemini, and other LLM providers to Claude Swarm"
  
  spec.add_dependency "claude-swarm", "~> 0.1"
  spec.add_dependency "ruby_llm", "~> 0.1"
  spec.add_dependency "ruby_llm-mcp", "~> 0.1"
end

# lib/claude_swarm_providers.rb
# Empty - just a dependency installer
```

## Unified Logging Format

### JSON Log Structure

Both Claude Code and RubyLLM events use the same wrapper:

```json
{
  "instance": "instance_name",
  "instance_id": "unique_id",
  "calling_instance": "caller_name",
  "calling_instance_id": "caller_id",
  "timestamp": "ISO8601",
  "provider": "claude-code|ruby_llm",
  "event": {
    // Provider-specific event data
  }
}
```

### Event Types

1. **Request**: Initial prompt
2. **Assistant**: AI response with content/tool calls
3. **Tool Use**: Tool invocation details
4. **Tool Result**: Tool execution results
5. **Result**: Final response with cost/duration
6. **Chunk**: Streaming response chunks (optional)

## Environment Variables

### Default Patterns
- `ANTHROPIC_API_KEY` - Claude/Anthropic
- `OPENAI_API_KEY` - OpenAI
- `GOOGLE_API_KEY` - Google Gemini
- `OPENAI_API_BASE` - Custom OpenAI endpoint

### Custom Patterns
- Via `api_key_env` config option
- Via `api_base_env` config option (OpenAI-compatible only)

## Benefits

1. **Zero Impact on Claude-Only Users**: No extra dependencies unless opted in
2. **Simple Activation**: Just add one gem to enable all providers
3. **Consistent Interface**: All providers work through the same MCP mechanism
4. **Unified Logging**: Single log format for analysis across providers
5. **Flexible Configuration**: Support for custom endpoints and auth
6. **Minimal Core Changes**: Mostly additive, preserving existing functionality

## Implementation Order

1. ✅ Create BaseExecutor abstract class
2. ✅ Create ExecutorFactory for clean provider selection
3. ✅ Update ClaudeCodeExecutor to inherit from BaseExecutor
4. ✅ Implement Provider Capabilities registry
5. ✅ Create ResponseNormalizer for unified output
6. ✅ Implement LlmExecutor with proper tool handling
7. ✅ Update ClaudeMcpServer to use ExecutorFactory
8. ✅ Add CLI options for provider configuration
9. ✅ Update McpGenerator for provider arguments
10. ✅ Create claude-swarm-providers extension gem
11. ✅ Update documentation with examples

## Testing Strategy

1. Core gem tests pass without provider gem
2. Provider gem tests cover all supported providers
3. Integration tests with mock MCP servers
4. End-to-end tests with real provider APIs (gated)
5. Test provider capability detection
6. Test response normalization across providers
7. Test tool compatibility handling
8. Test custom endpoint configuration

## Error Handling

### Provider-Specific Errors
- API key validation failures
- Model not found errors
- Rate limiting responses
- Network timeouts
- Invalid tool calls

### User-Friendly Messages
```ruby
case error
when RubyLlm::AuthenticationError
  "Authentication failed. Check your #{provider.upcase}_API_KEY environment variable."
when RubyLlm::ModelNotFoundError
  "Model '#{model}' not found for #{provider}. Set assume_model_exists: true for custom models."
when RubyLlm::RateLimitError
  "Rate limit exceeded for #{provider}. Please wait and try again."
end
```

## Performance Considerations

1. **Session Management**: Cache LLM contexts to avoid re-initialization
2. **Streaming**: Handle provider-specific chunk formats
3. **Concurrent Requests**: Respect provider-specific rate limits
4. **Cost Tracking**: Real-time token usage monitoring

## Security Considerations

1. **API Key Management**: Never log or expose API keys
2. **Environment Isolation**: Use separate contexts per instance
3. **Tool Execution**: Validate tool permissions per provider
4. **Network Security**: Support proxy configurations for enterprise