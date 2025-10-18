# Using Claude Code Agent Files

SwarmSDK supports loading agent definitions from Claude Code markdown files, allowing you to reuse your existing `.claude/agents/*.md` files with SwarmSDK.

## Overview

Claude Code agents use a different format than SwarmSDK agents:
- **Tools**: Comma-separated strings (e.g., `tools: Read, Write, Bash`)
- **Model shortcuts**: `sonnet`, `opus`, `haiku` instead of full model IDs
- **Tool permissions**: `Write(src/**)` syntax (not supported in frontmatter)

SwarmSDK automatically detects and converts Claude Code agent files to SwarmSDK format.

## Quick Start

### YAML Format

```yaml
version: 2
swarm:
  name: "Dev Team"
  lead: reviewer
  agents:
    # Simple path - uses file as-is
    reviewer: ".claude/agents/code-reviewer.md"

    # With overrides - customize for SwarmSDK
    implementer:
      agent_file: ".claude/agents/implementer.md"
      provider: openai
      model: gpt-5
      delegates_to: [reviewer]
```

### Ruby DSL Format

```ruby
SwarmSDK.build do
  name "Dev Team"
  lead :reviewer

  # Simple - uses file as-is
  agent :reviewer, File.read(".claude/agents/code-reviewer.md")

  # With overrides
  agent :implementer, File.read(".claude/agents/implementer.md") do
    provider :openai
    model "gpt-5"
    delegates_to :reviewer
  end
end
```

## Claude Code Agent File Format

Claude Code agent files use YAML frontmatter with markdown content:

```markdown
---
name: code-reviewer
description: Expert code reviewer
tools: Read, Grep, Glob, Write
model: sonnet
---

You are a senior code reviewer ensuring code quality.

Review checklist:
- Code is simple and readable
- No duplicated code
- Proper error handling
```

## Automatic Conversions

### Model Shortcuts

SwarmSDK automatically resolves model shortcuts to the latest model IDs:

| Shortcut | Resolves To |
|----------|-------------|
| `sonnet` | `claude-sonnet-4-5-20250929` |
| `opus` | `claude-opus-4-1-20250805` |
| `haiku` | `claude-haiku-4-5-20251001` |

**Note:** Mappings are defined in `lib/swarm_sdk/model_aliases.json` and can be updated as new models are released.

### Tools

Comma-separated tools are converted to arrays:

```markdown
# Claude Code format
tools: Read, Write, Bash

# Converts to SwarmSDK
tools: [Read, Write, Bash]
```

### Coding Agent Flag

Claude Code agent files automatically get `coding_agent: true` by default, which includes SwarmSDK's base system prompt for coding tasks.

## Handling Differences

### Tool Permissions

Claude Code's tool permission syntax (`Write(src/**)`) is **not supported** in agent frontmatter. You'll see a warning:

```
Tool permission syntax 'Write(src/**)' detected in agent file.
SwarmSDK supports permissions but uses different syntax.
Using 'Write' without restrictions for now.
See SwarmSDK documentation for permission configuration.
```

**Solution:** Configure permissions in your swarm file:

**YAML:**
```yaml
agents:
  reviewer:
    agent_file: ".claude/agents/reviewer.md"
    permissions:
      Write:
        allowed_paths: ["src/**"]
```

**Ruby DSL:**
```ruby
agent :reviewer, File.read(".claude/agents/reviewer.md") do
  permissions do
    tool(:Write).allow_paths("src/**")
  end
end
```

### Hooks

Hooks in Claude Code agent frontmatter are **not supported**. You'll see a warning:

```
Hooks configuration detected in agent frontmatter.
SwarmSDK handles hooks at the swarm level.
```

**Solution:** Configure hooks at the swarm or agent level in your configuration file.

## Overriding Settings

You can override any setting from the markdown file:

### Override Model

```yaml
agents:
  reviewer:
    agent_file: ".claude/agents/reviewer.md"
    model: gpt-5  # Override 'sonnet' from markdown
```

```ruby
agent :reviewer, File.read(".claude/agents/reviewer.md") do
  model "gpt-5"  # Override 'sonnet' from markdown
end
```

### Override Tools

```yaml
agents:
  reviewer:
    agent_file: ".claude/agents/reviewer.md"
    tools:  # Replaces tools from markdown
      - Read
      - Bash
```

```ruby
agent :reviewer, File.read(".claude/agents/reviewer.md") do
  tools :Read, :Bash, replace: true  # Replaces tools from markdown
end
```

### Add Provider/Base URL

```yaml
agents:
  reviewer:
    agent_file: ".claude/agents/reviewer.md"
    provider: openai
    base_url: "https://api.openrouter.ai/v1"
    headers:
      authorization: "Bearer ${OPENROUTER_API_KEY}"
```

```ruby
agent :reviewer, File.read(".claude/agents/reviewer.md") do
  provider :openai
  base_url "https://api.openrouter.ai/v1"
  headers authorization: "Bearer #{ENV['OPENROUTER_API_KEY']}"
end
```

## Model Validation

SwarmSDK validates models using its own registry (`lib/swarm_sdk/models.json`) and provides helpful suggestions:

```
⚠️ MODEL WARNING reviewer
  Model 'anthropic:claude-sonnet-4-5' not found in registry
  Did you mean one of these?
    • claude-sonnet-4-5-20250929 (200,000 tokens)
  Context tracking unavailable for this model.
```

**Note:** Warnings are informational only - execution continues. SwarmSDK always tells RubyLLM to assume models exist, then validates separately for better error messages.

## Best Practices

1. **Use model shortcuts** - `sonnet`, `opus`, `haiku` stay up-to-date automatically
2. **Keep agent files portable** - Don't put SwarmSDK-specific settings in frontmatter
3. **Override in swarm config** - Provider, base_url, permissions belong in swarm file
4. **Share agent files** - Same markdown file works in Claude Code and SwarmSDK

## Example: Full Integration

**Claude Code agent file** (`.claude/agents/backend-dev.md`):
```markdown
---
name: backend-developer
description: Backend API specialist
tools: Read, Write, Edit, Bash, Grep
model: sonnet
---

You are a backend developer specializing in REST APIs and databases.
Focus on scalability, security, and clean architecture.
```

**SwarmSDK config** (`swarm.yml`):
```yaml
version: 2
swarm:
  name: "Dev Team"
  lead: backend

  agents:
    backend:
      agent_file: ".claude/agents/backend-dev.md"
      provider: openai
      base_url: "http://localhost:8000/v1"  # Local proxy
      delegates_to: [reviewer]
      permissions:
        Write:
          allowed_paths: ["backend/**"]
```

This gives you the best of both worlds:
- ✅ Portable agent definitions (work in Claude Code)
- ✅ SwarmSDK-specific configuration (provider, permissions, delegation)
- ✅ No duplication or maintenance burden
