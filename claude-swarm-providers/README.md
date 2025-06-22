# Claude Swarm Providers

This gem adds multi-provider support to [Claude Swarm](https://github.com/parruda/claude-swarm), enabling you to use AI models from OpenAI, Google Gemini, Cohere, and other providers alongside Claude.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'claude-swarm-providers'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install claude-swarm-providers

## What This Gem Does

This is a metagem that simply installs the necessary dependencies:
- `ruby_llm` - Provides unified access to multiple LLM providers
- `ruby_llm-mcp` - Enables MCP (Model Context Protocol) support for ruby_llm

Once installed, Claude Swarm will automatically detect and enable multi-provider support.

## Usage

After installing this gem, you can use non-Anthropic models in your Claude Swarm configurations:

```yaml
version: 1
swarm:
  name: "Multi-Model Team"
  main: lead
  instances:
    lead:
      description: "Claude Opus lead"
      model: opus
      connections: [gpt_analyst, gemini_reviewer]
      
    gpt_analyst:
      provider: openai
      model: gpt-4-turbo
      description: "GPT-4 for analysis"
      api_key_env: OPENAI_API_KEY  # Optional, defaults to OPENAI_API_KEY
      
    gemini_reviewer:
      provider: google
      model: gemini-2.0-flash
      description: "Gemini with 2M context window"
```

## Supported Providers

- **OpenAI**: GPT-4, GPT-3.5, and other OpenAI models
- **Google**: Gemini models
- **Cohere**: Command and other Cohere models
- **Custom OpenAI-compatible endpoints**: Azure OpenAI, Ollama, etc.

### Custom Endpoints

For OpenAI-compatible APIs (like Azure OpenAI or Ollama):

```yaml
azure_gpt:
  provider: openai
  model: my-gpt4-deployment
  api_base_env: AZURE_OPENAI_BASE  # Custom base URL
  api_key_env: AZURE_OPENAI_KEY    # Custom API key
  assume_model_exists: true         # Skip model validation
```

## Environment Variables

Each provider requires an API key:

- `OPENAI_API_KEY` - For OpenAI models
- `GOOGLE_API_KEY` or `GEMINI_API_KEY` - For Google Gemini
- `COHERE_API_KEY` - For Cohere models

You can override these with custom environment variable names using the `api_key_env` configuration option.

## Features and Limitations

### Supported Features by Provider

| Provider | Streaming | Tools/Functions | System Prompts | Custom Base URL |
|----------|-----------|-----------------|----------------|-----------------|
| OpenAI   | ✅        | ✅              | ✅             | ✅              |
| Google   | ✅        | ❌              | ✅             | ❌              |
| Cohere   | ✅        | ✅              | ✅             | ❌              |

### Context Windows

- OpenAI: Up to 128k tokens
- Google Gemini: Up to 2M tokens
- Cohere: Up to 128k tokens

Note: Claude Swarm instances can only share context up to the minimum window size between connected instances.

## Development

This gem contains no actual code - it's purely a dependency installer. All provider implementation code lives in the main `claude-swarm` gem and is loaded conditionally when this gem is installed.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).