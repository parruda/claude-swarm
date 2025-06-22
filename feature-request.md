## Overview

Enable Claude Swarm to orchestrate AI agents using any model/provider supported by the ruby_llm gem (OpenAI, Google Gemini, Cohere, etc.), extending beyond Claude-only swarms. This feature will allow teams to leverage the unique strengths of different AI models within a single collaborative swarm.

## Motivation

- **Model Diversity**: Different models excel at different tasks (e.g., GPT-4 for general reasoning, Gemini for multimodal tasks, specialized models for domain-specific work)
- **Cost Optimization**: Mix expensive high-capability models with cheaper alternatives based on task requirements
- **Vendor Independence**: Avoid lock-in to a single AI provider
- **Specialized Expertise**: Create swarms that combine Claude's coding abilities with other models' strengths

## Proposed Solution

### Architecture

Extend Claude Swarm to support non-Claude models by:
1. Running non-Claude instances as stdio-based MCP servers
2. Allowing Claude instances to connect to these servers via the existing MCP protocol
3. Providing a unified configuration interface that abstracts provider differences

### Configuration Schema

Extend the existing YAML configuration with optional provider-specific fields:

```yaml
version: 1
swarm:
  name: "Multi-Model Dev Team"
  main: lead
  instances:
    lead:
      description: "Claude Opus lead coordinating the team"
      directory: .
      model: opus
      connections: [gpt_analyst, gemini_designer]
      tools: [Read, Edit, Bash, mcp__gpt_analyst, mcp__gemini_designer]
      
    gpt_analyst:
      provider: openai           # New field (defaults to "claude")
      model: gpt-4-turbo
      api_key_env: OPENAI_API_KEY  # Optional: custom env var
      description: "GPT-4 for complex analysis and architecture"
      directory: ./src
      tools: [Read, Analyze]
      connections: [filesystem]
      
    gemini_designer:
      provider: google
      model: gemini-pro
      description: "Gemini for design and documentation"
      directory: ./docs
      tools: [Read, Edit, Write]
```

## Implementation Plan

### New Components

1. **`ClaudeSwarm::LlmMcpServer`** - MCP server implementation for LLM instances
2. **`ClaudeSwarm::LlmTaskTool`** - Primary tool for task execution
3. **`ClaudeSwarm::LlmExecutor`** - Abstraction over ruby_llm
4. **CLI command** - Add `llm-serve` alongside existing `mcp-serve`

### Modified Components

- **Configuration** - Add provider and api_key_env fields
- **Orchestrator** - Route non-Claude instances to LLM launcher
- **McpGenerator** - Generate correct MCP configs for LLM servers

## Technical Considerations

- API keys managed via environment variables
- Session management follows existing patterns
- Each LLM instance runs as separate process
- Tool compatibility varies by provider

## Example Use Cases

### Multi-Model Code Review
```yaml
instances:
  claude_dev:
    model: opus
    connections: [gpt_reviewer]
    
  gpt_reviewer:
    provider: openai
    model: gpt-4-turbo
    prompt: "You are a senior code reviewer"
```

### Cost-Optimized Development
```yaml
instances:
  main:
    model: sonnet  # Cheaper for coordination
    connections: [opus_expert, gpt_helper]
    
  gpt_helper:
    provider: openai
    model: gpt-3.5-turbo  # Cheap for simple tasks
```

## Backward Compatibility

- No breaking changes
- Provider defaults to "claude" when omitted
- Existing swarms work unchanged

## Dependencies

- ruby_llm gem for multi-provider support
- ruby_llm-mcp gem for mcp client support for ruby llm
