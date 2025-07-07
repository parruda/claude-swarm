# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Claude Swarm is a Ruby gem that orchestrates multiple Claude Code instances as a collaborative AI development team. It enables running AI agents with specialized roles, tools, and directory contexts, communicating via MCP (Model Context Protocol).

## Development Commands

### Setup
```bash
bin/setup              # Install dependencies
```

### Testing
```bash
rake test             # Run the Minitest test suite
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
rake rubocop -A       # Run RuboCop linter to auto fix problems
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
4. The main instance is launched with `exec`, replacing the current process
5. Connected instances are available as MCP servers to the main instance
6. When an instance has connections, those connections are automatically added to its allowed tools as `mcp__<connection_name>`

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
