# LLM-MCP Integration

Claude Swarm now supports running instances with different LLM providers through the `llm-mcp` tool. This allows you to create swarms with mixed AI providers, combining Claude with OpenAI, custom models, or any provider supported by llm-mcp.

## Configuration

To use a non-Claude model for an instance, specify the `provider` and optionally `base_url` fields:

```yaml
instances:
  openai_instance:
    description: "Instance powered by OpenAI"
    directory: ./workspace
    model: gpt-4
    provider: openai
    base_url: https://api.openai.com/v1  # Optional custom API endpoint
    prompt: "You are an OpenAI-powered assistant"
    allowed_tools: [Read, Edit]
```

## Supported Fields

- `provider`: The LLM provider to use (e.g., `openai`, `anthropic`, `custom`)
- `base_url`: Optional custom API endpoint for the provider
- `model`: The model name (provider-specific)

## How It Works

1. When an instance has a `provider` field, Claude Swarm uses `LlmMcpExecutor` instead of `ClaudeCodeExecutor`
2. The executor launches `llm-mcp` with the appropriate arguments
3. Session management and logging work the same way across all providers
4. The main instance always uses Claude directly (not through MCP)

## Example Configuration

See `examples/llm-mcp-example.yml` for a complete example of a multi-provider swarm.

## Testing with Custom Providers

For testing with custom or local LLM providers:

```bash
claude-swarm --provider openai --model o3 --skip-model-validation --base-url https://your-proxy.local/v1
```

## Requirements

- The `llm-mcp` command must be available in your PATH
- Valid API credentials for the providers you want to use
- Network access to the provider endpoints