# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Claude Swarm is a Ruby gem that orchestrates multiple Claude Code instances as a collaborative AI development team. It enables running AI agents with specialized roles, tools, and directory contexts, communicating via MCP (Model Context Protocol).

SwarmCore is a complete reimagining of Claude Swarm that decouples from Claude Code and runs everything in a single process using RubyLLM for all LLM interactions. It is being developed in `lib/swarm_core`, and using the gemspec swarm-core.gemspec.

## Development Commands

### Testing
```bash
bundle exec rake test             # Run the Minitest test suite
```

**Important**: Tests should not generate any output to stdout or stderr. When writing tests:
- Capture or suppress all stdout/stderr output from tested methods
- Use `capture_io` or `capture_subprocess_io` for Minitest
- Redirect output streams to `StringIO` or `/dev/null` when necessary
- Mock or stub methods that produce console output
- Ensure clean test output for better CI/CD integration

Example:
```ruby
def test_command_with_output
  output, err = capture_io do
    # Code that produces output
  end
  # Test assertions here
end
```

### Linting
```bash
bundle exec rubocop -A       # Run RuboCop linter to auto fix problems
```

### Development Console
```bash
bin/console           # Start IRB session with gem loaded
```

### Build & Release
```bash
bundle exec rake install    # Install gem locally
bundle exec rake release    # Release gem to RubyGems.org
```

### Default Task
```bash
rake                  # Runs both tests and RuboCop
```

## Git Worktree Support

Claude Swarm supports launching instances in Git worktrees to isolate changes:

### CLI Usage
```bash
# Create worktrees with custom name
claude-swarm --worktree feature-branch

# Create worktrees with auto-generated name (worktree-SESSION_ID)
claude-swarm --worktree

# Short form
claude-swarm -w feature-x
```

### Per-Instance Configuration
Instances can have individual worktree settings that override CLI behavior:

```yaml
instances:
  main:
    worktree: true         # Use shared worktree name (from CLI or auto-generated)
  testing:
    worktree: false        # Don't use worktree for this instance
  feature:
    worktree: "feature-x"  # Use specific worktree name
  default:
    # No worktree field - follows CLI behavior
```

### Worktree Behavior
- Worktrees are created in external directory: `~/.claude-swarm/worktrees/[session_id]/[repo_name-hash]/[worktree_name]`
- This ensures proper isolation from the main repository and avoids conflicts with bundler and other tools
- Each unique Git repository gets its own worktree with the same name
- All instance directories are mapped to their worktree equivalents
- Worktrees are automatically cleaned up when the swarm exits
- Session metadata tracks worktree information for restoration
- Non-Git directories are used as-is without creating worktrees
- Existing worktrees with the same name are reused
- The `claude-swarm clean` command removes orphaned worktrees

## Claude Code SDK Integration

Claude Swarm uses the Claude Code SDK (`claude-code-sdk-ruby`) for all Claude instances. This provides:
- Better performance and reliability
- Structured message handling
- Improved error recovery
- Direct MCP server configuration support (stdio, sse, http)

The SDK executor handles all three MCP server types and properly converts MCP JSON configurations to SDK format.

## Architecture

The gem is fully implemented with the following components:

### Core Classes

- **ClaudeSwarm::CLI** (`lib/claude_swarm/cli.rb`): Thor-based CLI that handles command parsing and orchestration
- **ClaudeSwarm::Configuration** (`lib/claude_swarm/configuration.rb`): YAML parser and validator for swarm configurations
- **ClaudeSwarm::McpGenerator** (`lib/claude_swarm/mcp_generator.rb`): Generates MCP JSON configurations for each instance
- **ClaudeSwarm::Orchestrator** (`lib/claude_swarm/orchestrator.rb`): Launches the main Claude instance with proper configuration
- **ClaudeSwarm::WorktreeManager** (`lib/claude_swarm/worktree_manager.rb`): Manages Git worktrees for isolated development

### Key Features

1. **YAML Configuration**: Define swarms with instances, connections, tools, and MCP servers
2. **Inter-Instance Communication**: Instances connect via MCP using `claude mcp serve` with `-p` flag
3. **Tool Restrictions**: Support for tool restrictions using Claude's native pattern (connections are available as `mcp__instance_name`)
4. **Multiple MCP Types**: Supports both stdio and SSE MCP server types
5. **Automatic MCP Generation**: Creates `.claude-swarm/` directory with MCP configs
6. **Custom System Prompts**: Each instance can have a custom prompt via `--append-system-prompt`
7. **Git Worktree Support**: Run instances in isolated Git worktrees with per-instance configuration

### How It Works

1. User creates a `claude-swarm.yml` file defining the swarm topology
2. Running `claude-swarm` parses the configuration and validates it
3. MCP configuration files are generated for each instance in a session directory
4. Settings files (with hooks) are generated for each instance if hooks are configured
5. The main instance is launched with `exec`, replacing the current process
6. Connected instances are available as MCP servers to the main instance
7. When an instance has connections, those connections are automatically added to its allowed tools as `mcp__<connection_name>`

### Configuration Example

```yaml
version: 1
swarm:
  name: "Dev Team"
  main: lead
  instances:
    lead:
      description: "Lead developer coordinating the team"
      directory: .
      model: opus
      connections: [frontend, backend]
      prompt: "You are the lead developer coordinating the team"
      tools: [Read, Edit, Bash]
      worktree: true  # Optional: use worktree for this instance
    frontend:
      description: "Frontend developer specializing in React"
      directory: ./frontend
      model: sonnet
      prompt: "You specialize in frontend development with React"
      tools: [Edit, Write, Bash]
      worktree: false  # Optional: disable worktree for this instance
```

### Hooks Support

Claude Swarm supports configuring [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) for each instance. This allows you to run custom scripts before/after tools, on prompt submission, and more.

#### Configuration Example with Hooks

```yaml
version: 1
swarm:
  name: "Dev Team"
  main: lead
  instances:
    lead:
      description: "Lead developer"
      directory: .
      model: opus
      # Hooks configuration follows Claude Code's format exactly
      hooks:
        PreToolUse:
          - matcher: "Write|Edit"
            hooks:
              - type: "command"
                command: "$CLAUDE_PROJECT_DIR/.claude/hooks/validate-code.py"
                timeout: 10
        PostToolUse:
          - matcher: "Bash"
            hooks:
              - type: "command"
                command: "echo 'Command executed by lead' >> /tmp/lead.log"
        UserPromptSubmit:
          - hooks:
              - type: "command"
                command: "$CLAUDE_PROJECT_DIR/.claude/hooks/add-context.py"
    frontend:
      description: "Frontend developer"
      directory: ./frontend
      hooks:
        PreToolUse:
          - matcher: "Write"
            hooks:
              - type: "command"
                command: "npm run lint"
```

The hooks configuration is passed directly to Claude Code via a generated settings.json file in the session directory. Each instance gets its own settings file with its specific hooks.

## Testing

The gem includes comprehensive tests covering:
- Configuration parsing and validation
- MCP generation logic with connections
- Error handling scenarios
- CLI command functionality
- Session restoration
- Vibe mode behavior
- Worktree management and per-instance configuration

## Dependencies

- **thor** (~> 1.3): Command-line interface framework
- **yaml**: Built-in Ruby YAML parser (no explicit dependency needed)

## Zeitwerk Autoloading

This project uses Zeitwerk for automatic class loading. Important guidelines:

### Require Statement Rules

1. **DO NOT include any require statements for lib files**: Zeitwerk automatically loads all classes under `lib/claude_swarm/`. Never use `require`, `require_relative`, or `require "claude_swarm/..."` for internal project files.

2. **All dependencies must be consolidated in lib/claude_swarm.rb**: Both standard library and external gem dependencies are required at the top of `lib/claude_swarm.rb`. This includes:
   - Standard library dependencies (json, yaml, fileutils, etc.)
   - External gem dependencies (thor, openai, mcp_client, fast_mcp_annotations)

3. **No requires in other lib files**: Individual files in `lib/claude_swarm/` should not have any require statements. They rely on:
   - Dependencies loaded in `lib/claude_swarm.rb`
   - Other classes autoloaded by Zeitwerk

### Example

```ruby
# ✅ CORRECT - lib/claude_swarm.rb
# Standard library dependencies
require "json"
require "yaml"
require "fileutils"
# ... other standard libraries

# External dependencies
require "thor"
require "openai"
# ... other gems

# Zeitwerk setup
require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.setup

# ❌ INCORRECT - lib/claude_swarm/some_class.rb
require "json"  # Don't do this!
require_relative "other_class"  # Don't do this!
require "claude_swarm/configuration"  # Don't do this!
```

This approach ensures clean dependency management and leverages Ruby's modern autoloading capabilities.
