# Claude Swarm Multi-Model Extension

This extension enables Claude Swarm to orchestrate AI agents across different model providers beyond Anthropic's Claude models.

## Features

- Support for multiple LLM providers (OpenAI, Google Gemini, Groq, DeepSeek, Together AI, and local models)
- Automatic validation of provider configurations
- Seamless integration with Claude Swarm's MCP communication protocol
- Per-instance provider configuration

## Installation

Add this to your Gemfile:

```ruby
gem 'claude-swarm-multi-model'
gem 'ruby_llm' # Required dependency
```

Or install directly:

```bash
gem install claude-swarm-multi-model ruby_llm
```

## Configuration

### Basic Usage

In your `claude-swarm.yml`, specify the provider and model for each instance:

```yaml
version: 1
swarm:
  name: "Multi-Model Team"
  main: lead
  instances:
    lead:
      description: "Lead developer using Claude"
      directory: .
      model: claude-3-5-sonnet-20241022
      # No provider specified - defaults to Anthropic
      
    assistant:
      description: "Assistant using GPT-4"
      directory: .
      provider: openai
      model: gpt-4o
      
    analyst:
      description: "Data analyst using Gemini"
      directory: ./data
      provider: gemini
      model: gemini-1.5-pro
```

### Supported Providers

Run `claude-swarm list-providers` to see all available providers and models.

#### OpenAI
- **Models**: gpt-4o, gpt-4o-mini, gpt-4-turbo, gpt-4, gpt-3.5-turbo, o1-preview, o1-mini
- **API Key**: Set `OPENAI_API_KEY` environment variable

#### Google Gemini
- **Models**: gemini-2.0-flash-exp, gemini-1.5-pro, gemini-1.5-flash, gemini-1.0-pro
- **API Key**: Set `GEMINI_API_KEY` environment variable

#### Groq
- **Models**: llama-3.3-70b-versatile, llama-3.1-8b-instant, mixtral-8x7b-32768, gemma2-9b-it
- **API Key**: Set `GROQ_API_KEY` environment variable

#### DeepSeek
- **Models**: deepseek-chat, deepseek-coder
- **API Key**: Set `DEEPSEEK_API_KEY` environment variable

#### Together AI
- **Models**: meta-llama/Llama-3.2-90B-Vision-Instruct-Turbo, meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo
- **API Key**: Set `TOGETHER_API_KEY` environment variable

#### Local Models
- **Models**: Any model supported by your local server
- **Base URL**: Set `LOCAL_LLM_BASE_URL` environment variable
- **API Key**: Not required

### Environment Variables

Before running a swarm with non-Anthropic providers, ensure the required environment variables are set:

```bash
export OPENAI_API_KEY="your-openai-key"
export GEMINI_API_KEY="your-gemini-key"
# etc...
```

## How It Works

The extension hooks into Claude Swarm's configuration and MCP generation process:

1. **Configuration Validation**: When a swarm configuration is loaded, the extension validates that:
   - Specified providers are supported
   - Models are valid for the chosen provider
   - Required API keys are set

2. **MCP Server Replacement**: For non-Anthropic instances, the extension replaces the standard `claude mcp serve` command with `claude-swarm-multi-model llm-serve`, which acts as a bridge between Claude's MCP protocol and the chosen LLM provider.

3. **Transparent Communication**: From the main Claude instance's perspective, all connected instances appear as standard MCP servers, regardless of which LLM provider they're using.

## Development

### Running Tests

```bash
bundle exec rake test
```

### Adding New Providers

To add support for a new provider:

1. Add the provider configuration to `PROVIDERS` hash in `lib/claude_swarm_multi_model/config_validator.rb`
2. Implement the provider adapter in `lib/claude_swarm_multi_model/providers/`
3. Update the MCP server to handle the new provider

## License

See LICENSE file in the root directory.