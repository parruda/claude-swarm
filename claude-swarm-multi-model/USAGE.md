# Claude Swarm Multi-Model Usage Guide

## Installation

1. Install the claude-swarm-multi-model gem:
```bash
gem install claude-swarm-multi-model
```

2. Ensure you have API keys for the providers you want to use:
```bash
export OPENAI_API_KEY=your_openai_key
export GEMINI_API_KEY=your_gemini_key
export GROQ_API_KEY=your_groq_key
# etc.
```

## Configuration

Add provider information to your swarm configuration:

```yaml
version: 1
swarm:
  name: "Multi-Model Team"
  main: lead
  instances:
    lead:
      description: "Team lead using Claude"
      directory: .
      model: opus
      connections: [gpt_analyst, gemini_dev]
    
    gpt_analyst:
      description: "OpenAI GPT-4 for analysis"
      directory: ./docs
      provider: openai  # Explicitly set provider
      model: gpt-4-turbo
      api_key_env: OPENAI_API_KEY  # Environment variable for API key
    
    gemini_dev:
      description: "Google Gemini for development"
      directory: ./src
      # Provider auto-detected from model name
      model: gemini-1.5-pro
      api_key_env: GEMINI_API_KEY
```

## Provider Auto-Detection

The gem automatically detects providers based on model names:

- `gpt-*` → OpenAI
- `gemini-*` → Gemini (Google)
- `groq-*` → Groq
- `deepseek-*` → DeepSeek
- `together-*` → Together AI
- `claude-*`, `opus`, `sonnet`, `haiku` → Anthropic (default)

## Supported Providers

### OpenAI
- Models: gpt-4-turbo, gpt-4o, gpt-4o-mini, gpt-3.5-turbo
- API Key: `OPENAI_API_KEY`
- Base URL: `OPENAI_BASE_URL` (optional)

### Google Gemini
- Models: gemini-1.5-pro, gemini-1.5-flash, gemini-1.0-pro
- API Key: `GEMINI_API_KEY`
- Base URL: `GEMINI_BASE_URL` (optional)

### Groq
- Models: groq-llama-3.1-70b, groq-mixtral-8x7b
- API Key: `GROQ_API_KEY`
- Base URL: `GROQ_BASE_URL` (optional)

### DeepSeek
- Models: deepseek-chat, deepseek-coder
- API Key: `DEEPSEEK_API_KEY`
- Base URL: `DEEPSEEK_BASE_URL` (optional)

### Together AI
- Models: together-llama-3-70b, together-mixtral-8x22b
- API Key: `TOGETHER_API_KEY`
- Base URL: `TOGETHER_BASE_URL` (optional)

### Local LLMs
- Models: Any model name
- No API key required
- Base URL: `LOCAL_LLM_BASE_URL` (required)

## Running Multi-Model Swarms

1. Create your configuration file (e.g., `team.yml`)
2. Run the swarm:
```bash
claude-swarm team.yml
```

## CLI Commands

The gem adds new commands to claude-swarm:

```bash
# List available providers and models
claude-swarm list-providers

# Start an LLM MCP server directly (for testing)
claude-swarm llm-serve --provider openai --model gpt-4-turbo
```

## Custom Base URLs

For self-hosted or proxy endpoints:

```yaml
gpt_custom:
  provider: openai
  model: gpt-4-turbo
  api_key_env: CUSTOM_API_KEY
  base_url_env: CUSTOM_BASE_URL  # Points to your custom endpoint
```

## Session Management

Multi-model sessions are tracked in the same `session.log` format:
- Token usage per provider
- Cost tracking (when available)
- Provider metadata in session files
- Seamless session restoration

## Example: Mixed Provider Team

```yaml
version: 1
swarm:
  name: "Full Stack AI Team"
  main: architect
  instances:
    architect:
      description: "Chief architect using Claude Opus"
      directory: .
      model: opus
      connections: [frontend, backend, reviewer, tester]
      prompt: "You are the chief architect coordinating a diverse AI team"
    
    frontend:
      description: "Frontend specialist using GPT-4"
      directory: ./frontend
      provider: openai
      model: gpt-4-turbo
      api_key_env: OPENAI_API_KEY
      prompt: "You specialize in React and modern frontend development"
    
    backend:
      description: "Backend developer using Gemini"
      directory: ./backend
      model: gemini-1.5-pro
      api_key_env: GEMINI_API_KEY
      prompt: "You are an expert in Ruby on Rails and APIs"
    
    reviewer:
      description: "Code reviewer using Groq"
      directory: .
      provider: groq
      model: groq-mixtral-8x7b
      api_key_env: GROQ_API_KEY
      prompt: "You are a meticulous code reviewer"
    
    tester:
      description: "Test engineer using local LLM"
      directory: ./test
      provider: local
      model: codellama:latest
      base_url_env: OLLAMA_BASE_URL
      prompt: "You write comprehensive test suites"
```

## Troubleshooting

1. **Missing API Key**: Ensure the environment variable is set
2. **Provider Not Found**: Check the provider name spelling
3. **Model Not Supported**: Verify the model is in the supported list
4. **Connection Failed**: Check network and base URL settings

## Best Practices

1. Use environment variables for API keys (never commit them)
2. Choose models based on task requirements and cost
3. Set appropriate rate limits for each provider
4. Monitor token usage across providers
5. Use local models for sensitive data