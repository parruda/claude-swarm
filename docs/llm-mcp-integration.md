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
    temperature: 0.7  # Optional temperature for response randomness
    prompt: "You are an OpenAI-powered assistant"
    allowed_tools: [Read, Edit]
```

## Supported Fields

- `provider`: The LLM provider to use (e.g., `openai`, `anthropic`, `custom`)
- `base_url`: Optional custom API endpoint for the provider
- `model`: The model name (provider-specific)
- `temperature`: Optional temperature parameter for controlling randomness (0.0-1.0)
- `reasoning_effort`: Optional reasoning effort level for OpenAI o3/o4 models (low, medium, high)

## Temperature Settings

The `temperature` parameter controls the randomness of model responses:
- **Low temperature (0.0-0.3)**: More deterministic, focused, and consistent responses. Good for coding and precise tasks.
- **Medium temperature (0.4-0.7)**: Balanced creativity and consistency. Good for general tasks.
- **High temperature (0.8-1.0)**: More creative, varied, and unpredictable responses. Good for brainstorming and creative writing.

Example use cases:
```yaml
instances:
  precise_coder:
    provider: openai
    model: gpt-4
    temperature: 0.2  # Consistent, deterministic coding
    
  creative_writer:
    provider: openai
    model: gpt-4
    temperature: 0.9  # Creative, varied responses
```

## Reasoning Effort (OpenAI o3/o4 Models)

The `reasoning_effort` parameter controls the computational effort for OpenAI's o3 and o4 series models:
- **low**: Faster responses with less computational effort
- **medium**: Balanced performance and quality
- **high**: Maximum quality with more computational effort

This parameter is only available for the following OpenAI models:
- `o3`
- `o3-pro`
- `o4-mini`
- `o4-mini-high`

Example configuration:
```yaml
instances:
  reasoning_assistant:
    provider: openai
    model: o3
    reasoning_effort: medium
    description: "Assistant using OpenAI o3 with medium reasoning effort"
    
  high_quality_analyst:
    provider: openai
    model: o3-pro
    reasoning_effort: high
    temperature: 0.3
    description: "High-quality analysis with maximum reasoning effort"
```

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