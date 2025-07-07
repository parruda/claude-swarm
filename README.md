# Claude Swarm

[![Gem Version](https://badge.fury.io/rb/claude_swarm.svg?cache_bust=0.1.17)](https://badge.fury.io/rb/claude_swarm)
[![CI](https://github.com/parruda/claude-swarm/actions/workflows/ci.yml/badge.svg)](https://github.com/parruda/claude-swarm/actions/workflows/ci.yml)

Claude Swarm orchestrates multiple Claude Code instances as a collaborative AI development team. It enables running AI agents with specialized roles, tools, and directory contexts, communicating via MCP (Model Context Protocol) in a tree-like hierarchy. Define your swarm topology in simple YAML and let Claude instances delegate tasks through connected instances. Perfect for complex projects requiring specialized AI agents for frontend, backend, testing, DevOps, or research tasks.

## Table of Contents

- [Installation](#installation)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
  - [Quick Start](#quick-start)
  - [Configuration Format](#configuration-format)
  - [MCP Server Types](#mcp-server-types)
  - [Tools](#tools)
  - [Examples](#examples)
  - [Command Line Options](#command-line-options)
  - [Session Monitoring](#session-monitoring)
  - [Session Management and Restoration](#session-management-and-restoration-experimental)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Installation

Install [Claude CLI](https://docs.anthropic.com/en/docs/claude-code/overview) if you haven't already:

```bash
npm install -g @anthropic-ai/claude-code
```

Install this gem by executing:

```bash
gem install claude_swarm
```

Or add it to your Gemfile:

```ruby
gem 'claude_swarm'
```

Then run:

```bash
bundle install
```

## Prerequisites

- Ruby 3.2.0 or higher
- Claude CLI installed and configured
- Any MCP servers you plan to use (optional)

## Usage

### Quick Start

1. Run `claude-swarm init` to create a basic template, or use `claude-swarm generate` for an interactive configuration experience with Claude's help. You can also manually create a `claude-swarm.yml` file in your project:

```yaml
version: 1
swarm:
  name: "My Dev Team"
  main: lead
  instances:
    lead:
      description: "Team lead coordinating development efforts"
      directory: .
      model: opus
      connections: [frontend, backend]
      vibe: true   # Allow all tools for this instance
    frontend:
      description: "Frontend specialist handling UI and user experience"
      directory: ./frontend
      model: opus
      allowed_tools:  # Tools aren't required if you run it with `--vibe`
        - Edit
        - Write
        - Bash
    backend:
      description: "Backend developer managing APIs and data layer"
      directory: ./backend  
      model: opus
      allowed_tools:
        - Edit
        - Write
        - Bash
```

2. Start the swarm:

```bash
claude-swarm
```
or if you are feeling the vibes...
```bash
claude-swarm --vibe # That will allow ALL tools for all instances! Be Careful!
```

This will:
- Launch the main instance (lead) with connections to other instances
- The lead instance can communicate with the other instances via MCP
- All session files are stored in `~/.claude-swarm/sessions/{project}/{timestamp}/` (customizable via `CLAUDE_SWARM_HOME`)

#### Multi-Level Swarm Example

Here's a more complex example showing specialized teams working on different parts of a project:

```yaml
version: 1
swarm:
  name: "Multi-Service Development Team"
  main: architect
  instances:
    architect:
      description: "System architect coordinating between service teams"
      directory: .
      model: opus
      connections: [frontend_lead, backend_lead, mobile_lead, devops]
      prompt: "You are the system architect coordinating between different service teams"
      allowed_tools: [Read, Edit, WebSearch]
    
    frontend_lead:
      description: "Frontend team lead overseeing React development"
      directory: ./web-frontend
      model: opus
      connections: [react_dev, css_expert]
      prompt: "You lead the web frontend team working with React"
      allowed_tools: [Read, Edit, Bash]
    
    react_dev:
      description: "React developer specializing in components and state management"
      directory: ./web-frontend/src
      model: opus
      prompt: "You specialize in React components and state management"
      allowed_tools: [Edit, Write, Bash]
    
    css_expert:
      description: "CSS specialist handling styling and responsive design"
      directory: ./web-frontend/styles
      model: opus
      prompt: "You handle all CSS and styling concerns"
      allowed_tools: [Edit, Write, Read]
    
    backend_lead:
      description: "Backend team lead managing API development"
      directory: ./api-server
      model: opus
      connections: [api_dev, database_expert]
      prompt: "You lead the API backend team"
      allowed_tools: [Read, Edit, Bash]
    
    api_dev:
      description: "API developer building REST endpoints"
      directory: ./api-server/src
      model: opus
      prompt: "You develop REST API endpoints"
      allowed_tools: [Edit, Write, Bash]
    
    database_expert:
      description: "Database specialist managing schemas and migrations"
      directory: ./api-server/db
      model: opus
      prompt: "You handle database schema and migrations"
      allowed_tools: [Edit, Write, Bash]
    
    mobile_lead:
      description: "Mobile team lead coordinating cross-platform development"
      directory: ./mobile-app
      model: opus
      connections: [ios_dev, android_dev]
      prompt: "You coordinate mobile development across platforms"
      allowed_tools: [Read, Edit]
    
    ios_dev:
      description: "iOS developer building native Apple applications"
      directory: ./mobile-app/ios
      model: opus
      prompt: "You develop the iOS application"
      allowed_tools: [Edit, Write, Bash]
    
    android_dev:
      description: "Android developer creating native Android apps"
      directory: ./mobile-app/android
      model: opus
      prompt: "You develop the Android application"
      allowed_tools: [Edit, Write, Bash]
    
    devops:
      description: "DevOps engineer managing CI/CD and infrastructure"
      directory: ./infrastructure
      model: opus
      prompt: "You handle CI/CD and infrastructure"
      allowed_tools: [Read, Edit, Bash]
```

In this setup:
- The architect (main instance) can delegate tasks to team leads
- Each team lead can work with their specialized developers
- Each instance is independent - connections create separate MCP server instances
- Teams work in isolated directories with role-appropriate tools
- Connected instances are accessible via MCP tools like `mcp__frontend_lead__task`, `mcp__backend_lead__task`, etc.


### Configuration Format

#### Top Level

```yaml
version: 1  # Required, currently only version 1 is supported
swarm:
  name: "Swarm Name"  # Display name for your swarm
  main: instance_key  # Which instance to launch as the main interface
  before:  # Optional: commands to run before launching the swarm
    - "echo 'Setting up environment...'"
    - "npm install"
    - "docker-compose up -d"
  instances:
    # Instance definitions...
```

#### Environment Variable Interpolation

Claude Swarm supports environment variable interpolation in all configuration values using the `${ENV_VAR_NAME}` syntax:

```yaml
version: 1
swarm:
  name: "${APP_NAME} Development Team"
  main: lead
  instances:
    lead:
      description: "Lead developer for ${APP_NAME}"
      directory: "${PROJECT_ROOT}"
      model: "${CLAUDE_MODEL}"
      prompt: "You are developing ${APP_NAME} version ${APP_VERSION}"
      allowed_tools: ["${TOOL_1}", "${TOOL_2}", "Bash"]
      mcps:
        - name: github
          type: stdio
          command: "${MCP_GITHUB_PATH}"
          env:
            GITHUB_TOKEN: "${GITHUB_TOKEN}"
```

Features:
- Variables are interpolated recursively in strings, arrays, and nested structures
- Multiple variables can be used in the same string
- Partial string interpolation is supported (e.g., `"prefix-${VAR}-suffix"`)
- If a referenced environment variable is not set, Claude Swarm will exit with a clear error message
- Non-matching patterns like `$VAR` or `{VAR}` are preserved as-is

#### Instance Configuration

Each instance must have:

- **description** (required): Brief description of the agent's role (used in task tool descriptions)

Each instance can have:

- **directory**: Working directory for this instance (can use ~ for home). Can be a string for a single directory or an array of strings for multiple directories
- **model**: Claude model to use (opus, sonnet)
- **connections**: Array of other instances this one can communicate with
- **allowed_tools**: Array of tools this instance can use (backward compatible with `tools`)
- **disallowed_tools**: Array of tools to explicitly deny (takes precedence over allowed_tools)
- **mcps**: Array of additional MCP servers to connect
- **prompt**: Custom system prompt to append to the instance
- **vibe**: Enable vibe mode (--dangerously-skip-permissions) for this instance (default: false)
- **worktree**: Configure Git worktree usage for this instance (true/false/string)
- **provider**: AI provider to use - "claude" (default) or "openai"

#### OpenAI Provider Configuration

When using `provider: openai`, the following additional fields are available:

- **temperature**: Temperature for OpenAI models (default: 0.3)
- **api_version**: API version to use - "chat_completion" (default) or "responses"
- **openai_token_env**: Environment variable name for OpenAI API key (default: "OPENAI_API_KEY")
- **base_url**: Custom base URL for OpenAI API (optional)

Note: OpenAI instances default to and ONLY operate as `vibe: true` and use MCP for tool access. By default it comes with Claude Code tools, connected with MCP to `claude mcp serve`.

```yaml
instance_name:
  description: "Specialized agent focused on specific tasks"
  directory: ~/project/path
  model: opus
  connections: [other_instance1, other_instance2]
  prompt: "You are a specialized agent focused on..."
  vibe: false  # Set to true to skip all permission checks for this instance
  allowed_tools:
    - Read
    - Edit
    - Write
    - Bash
    - WebFetch
    - WebSearch
  disallowed_tools:  # Optional: explicitly deny specific tools
    - "Write(*.log)"
    - "Bash(rm:*)"
  mcps:
    - name: server_name
      type: stdio
      command: command_to_run
      args: ["arg1", "arg2"]
      env:
        VAR1: value1

# OpenAI instance example
openai_instance:
  description: "OpenAI-powered creative assistant"
  provider: openai
  model: gpt-4o
  temperature: 0.7
  api_version: chat_completion
  openai_token_env: OPENAI_API_KEY
  prompt: "You are a creative assistant specializing in content generation"
```

### MCP Server Types

#### stdio (Standard I/O)
```yaml
mcps:
  - name: my_tool
    type: stdio
    command: /path/to/executable
    args: ["--flag", "value"]
    env:
      API_KEY: "secret"
```

#### sse (Server-Sent Events)
```yaml
mcps:
  - name: remote_api
    type: sse
    url: "https://api.example.com/mcp"
```

### Tools

Specify which tools each instance can use:

```yaml
allowed_tools:
  - Bash           # Command execution
  - Edit           # File editing
  - Write          # File creation
  - Read           # File reading
  - WebFetch       # Fetch web content
  - WebSearch      # Search the web

# Note: Pattern-based tool restrictions have been deprecated.
# Use allowed_tools and disallowed_tools with tool names only.
```

Tools are passed to Claude using the `--allowedTools` and `--disallowedTools` flags with comma-separated values. Disallowed tools take precedence over allowed tools.

#### Available Tools

```yaml
allowed_tools:
  - Read          # File reading
  - Edit          # File editing
  - Write         # File creation
  - Bash          # Command execution
  - WebFetch      # Fetch web content
  - WebSearch     # Search the web
```

### Examples

#### Full Stack Development Team

```yaml
version: 1
swarm:
  name: "Full Stack Team"
  main: architect
  instances:
    architect:
      description: "Lead architect responsible for system design and code quality"
      directory: .
      model: opus
      connections: [frontend, backend, devops]
      prompt: "You are the lead architect responsible for system design and code quality"
      allowed_tools:
        - Read
        - Edit
        - WebSearch
        
    frontend:
      description: "Frontend developer specializing in React and TypeScript"
      directory: ./frontend
      model: opus
      connections: [architect]
      prompt: "You specialize in React, TypeScript, and modern frontend development"
      allowed_tools:
        - Edit
        - Write
        - Bash
        
    backend:
      description: "Backend developer building APIs and services"
      directory: ./backend
      model: opus
      connections: [database]
      allowed_tools:
        - Edit
        - Write
        - Bash
        
    database:
      description: "Database administrator managing data persistence"
      directory: ./db
      model: sonnet
      allowed_tools:
        - Read
        - Bash
        
    devops:
      description: "DevOps engineer handling deployment and infrastructure"
      directory: .
      model: opus
      connections: [architect]
      allowed_tools:
        - Read
        - Edit
        - Bash
```

#### Research Team with External Tools

```yaml
version: 1
swarm:
  name: "Research Team"
  main: lead_researcher
  instances:
    lead_researcher:
      description: "Lead researcher coordinating analysis and documentation"
      directory: ~/research
      model: opus
      connections: [data_analyst, writer]
      allowed_tools:
        - Read
        - WebSearch
        - WebFetch
      mcps:
        - name: arxiv
          type: sse
          url: "https://arxiv-mcp.example.com"
          
    data_analyst:
      description: "Data analyst processing research data and statistics"
      directory: ~/research/data
      model: opus
      allowed_tools:
        - Read
        - Write
        - Bash
      mcps:
        - name: jupyter
          type: stdio
          command: jupyter-mcp
          args: ["--notebook-dir", "."]
          
    writer:
      description: "Technical writer preparing research documentation"
      directory: ~/research/papers
      model: opus
      allowed_tools:
        - Edit
        - Write
        - Read
```

#### Multi-Directory Support

Instances can have access to multiple directories using an array (uses `claude --add-dir`):

```yaml
version: 1
swarm:
  name: "Multi-Module Project"
  main: fullstack_dev
  instances:
    fullstack_dev:
      description: "Full-stack developer working across multiple modules"
      directory: [./frontend, ./backend, ./shared]  # Access to multiple directories
      model: opus
      allowed_tools: [Read, Edit, Write, Bash]
      prompt: "You work across frontend, backend, and shared code modules"
      
    documentation_writer:
      description: "Documentation specialist with access to code and docs"
      directory: ["./docs", "./src", "./examples"]  # Multiple directories as array
      model: sonnet
      allowed_tools: [Read, Write, Edit]
      prompt: "You maintain documentation based on code and examples"
```

When using multiple directories:
- The first directory in the array is the primary working directory
- Additional directories are accessible via the `--add-dir` flag in Claude
- All directories must exist or the configuration will fail validation

#### Mixed AI Provider Team

Combine Claude and OpenAI instances in a single swarm:

```yaml
version: 1
swarm:
  name: "Mixed AI Development Team"
  main: lead_developer
  instances:
    lead_developer:
      description: "Claude lead developer coordinating the team"
      directory: .
      model: opus
      connections: [creative_assistant, backend_dev]
      prompt: "You are the lead developer coordinating a mixed AI team"
      allowed_tools: [Read, Edit, Bash, Write]
      
    creative_assistant:
      description: "OpenAI-powered assistant for creative and UI/UX tasks"
      provider: openai
      model: gpt-4o
      temperature: 0.7
      directory: ./frontend
      prompt: "You are a creative frontend developer specializing in UI/UX design"
      # OpenAI instances default to vibe: true
      
    backend_dev:
      description: "Claude backend developer for system architecture"
      directory: ./backend
      model: sonnet
      prompt: "You specialize in backend development and system architecture"
      allowed_tools: [Read, Edit, Write, Bash]
```

Note: OpenAI instances require the API key to be set in the environment variable (default: `OPENAI_API_KEY`).

#### Before Commands

You can specify commands to run before launching the swarm using the `before` field:

```yaml
version: 1
swarm:
  name: "Development Environment"
  main: lead_developer
  before:
    - "echo '🚀 Setting up development environment...'"
    - "npm install"
    - "docker-compose up -d"
    - "bundle install"
  instances:
    lead_developer:
      description: "Lead developer coordinating the team"
      directory: .
      model: opus
      allowed_tools: [Read, Edit, Write, Bash]
```

The `before` commands:
- Are executed in sequence before launching any Claude instances
- Execute in the main instance's directory (including worktree if enabled)
- Must all succeed for the swarm to launch (exit code 0)
- Are only executed on initial swarm launch, not when restoring sessions
- Have their output logged to the session log file
- Will abort the swarm launch if any command fails

This is useful for:
- Installing dependencies in the isolated worktree environment
- Starting required services (databases, Docker containers, etc.)
- Setting up the development environment
- Running any prerequisite setup scripts
- Ensuring setup commands affect only the working directory, not the original repository


#### Mixed Permission Modes

You can have different permission modes for different instances:

```yaml
version: 1
swarm:
  name: "Mixed Mode Team"
  main: lead
  instances:
    lead:
      description: "Lead with full permissions"
      directory: .
      model: opus
      vibe: true  # This instance runs with --dangerously-skip-permissions
      connections: [restricted_worker, trusted_worker]
      
    restricted_worker:
      description: "Worker with restricted permissions"
      directory: ./sensitive
      model: sonnet
      allowed_tools: [Read, Bash]  # Allow read and bash commands
      
    trusted_worker:
      description: "Trusted worker with more permissions"
      directory: ./workspace
      model: sonnet
      vibe: true  # This instance also skips permissions
      allowed_tools: []  # Tools list ignored when vibe: true
```

#### Git Worktrees

Claude Swarm supports running instances in Git worktrees, allowing isolated work without affecting your main repository state. Worktrees are created in an external directory (`~/.claude-swarm/worktrees/`) to ensure proper isolation from the main repository and avoid conflicts with bundler and other tools.

**Example Structure:**
```
~/.claude-swarm/worktrees/
└── [session_id]/
    ├── my-repo-[hash]/
    │   └── feature-x/     (worktree for feature-x branch)
    └── other-repo-[hash]/
        └── feature-x/     (worktree for feature-x branch)
```

**CLI Option:**
```bash
# Create worktrees with auto-generated name (worktree-SESSION_ID)
claude-swarm --worktree

# Create worktrees with custom name
claude-swarm --worktree feature-branch

# Short form
claude-swarm -w
```

**Per-Instance Configuration:**
```yaml
version: 1
swarm:
  name: "Worktree Example"
  main: lead
  instances:
    lead:
      description: "Lead developer"
      directory: .
      worktree: true  # Use shared worktree name from CLI (or auto-generate)
      
    testing:
      description: "Test developer"  
      directory: ./tests
      worktree: false  # Don't use worktree for this instance
      
    feature_dev:
      description: "Feature developer"
      directory: ./features
      worktree: "feature-x"  # Use specific worktree name
```

**Worktree Behavior:**
- `worktree: true` - Uses the shared worktree name (from CLI or auto-generated)
- `worktree: false` - Disables worktree for this instance
- `worktree: "name"` - Uses a specific worktree name
- Omitted - Follows CLI behavior (use worktree if `--worktree` is specified)

**Notes:**
- Auto-generated worktree names use the session ID (e.g., `worktree-20241206_143022`)
- This makes it easy to correlate worktrees with their Claude Swarm sessions
- Worktrees are stored externally in `~/.claude-swarm/worktrees/[session_id]/`
- All worktrees are automatically cleaned up when the swarm exits
- Worktrees with the same name across different repositories share that name
- Non-Git directories are unaffected by worktree settings
- Existing worktrees with the same name are reused
- The `claude-swarm clean` command also removes orphaned worktrees

### Command Line Options

```bash
# Use default claude-swarm.yml in current directory
claude-swarm

# Specify a different configuration file
claude-swarm --config my-swarm.yml
claude-swarm -c team-config.yml

# Run with --dangerously-skip-permissions for all instances
claude-swarm --vibe

# Run in non-interactive mode with a prompt
claude-swarm -p "Implement the new user authentication feature"
claude-swarm --prompt "Fix the bug in the payment module"

# Resume a previous session by ID
claude-swarm --session-id 20241206_143022
claude-swarm --session-id ~/path/to/session

# Run all instances in Git worktrees
claude-swarm --worktree                  # Auto-generated name (worktree-SESSION_ID)
claude-swarm --worktree feature-branch   # Custom worktree name
claude-swarm -w                          # Short form

# Initialize a new configuration file
claude-swarm init
claude-swarm init --force  # Overwrite existing file

# Generate configuration interactively with Claude's help
claude-swarm generate                       # Claude names file based on swarm function
claude-swarm generate -o my-swarm.yml       # Custom output file
claude-swarm generate --model opus          # Use a specific model

# Show version
claude-swarm version

# Note: The permission MCP server has been deprecated. 
# Tool permissions are now handled through allowed_tools and disallowed_tools in your configuration.

# Internal command for MCP server (used by connected instances)
claude-swarm mcp-serve INSTANCE_NAME --config CONFIG_FILE --session-timestamp TIMESTAMP
```

### Session Monitoring

Claude Swarm provides commands to monitor and inspect running sessions:

```bash
# List running swarm sessions with costs and uptime
claude-swarm ps

# Show detailed information about a session including instance hierarchy
claude-swarm show 20250617_235233

# Watch live logs from a session
claude-swarm watch 20250617_235233

# Watch logs starting from the last 50 lines
claude-swarm watch 20250617_235233 -n 50

# List all available sessions (including completed ones)
claude-swarm list-sessions
claude-swarm list-sessions --limit 20

# Clean up stale session symlinks and orphaned worktrees
claude-swarm clean

# Remove sessions and worktrees older than 30 days
claude-swarm clean --days 30
```

Example output from `claude-swarm ps`:
```
⚠️  Total cost does not include the cost of the main instance

SESSION_ID       SWARM_NAME                 TOTAL_COST    UPTIME      DIRECTORY
-------------------------------------------------------------------------------
20250617_235233  Feature Development        $0.3847       15m         .
20250617_143022  Bug Investigation          $1.2156       1h          .
20250617_091547  Multi-Module Dev           $0.8932       30m         ./frontend, ./backend, ./shared
```

Note: The total cost shown reflects only the costs of connected instances called via MCP. The main instance cost is not tracked when running interactively.

Example output from `claude-swarm show`:
```
Session: 20250617_235233
Swarm: Feature Development
Total Cost: $0.3847 (excluding main instance)
Start Directory: /Users/paulo/project

Instance Hierarchy:
--------------------------------------------------
├─ orchestrator [main] (orchestrator_e85036fc)
   Cost: n/a (interactive) | Calls: 0
   └─ test_archaeologist (test_archaeologist_c504ca5f)
      Cost: $0.1925 | Calls: 1
   └─ pr_analyst (pr_analyst_bfbefe56)
      Cost: $0.1922 | Calls: 1

Note: Main instance (orchestrator) cost is not tracked in interactive mode.
      View costs directly in the Claude interface.
```

### Session Management and Restoration (Experimental)

Claude Swarm provides experimental session management with restoration capabilities. **Note: This feature is experimental and has limitations - the main instance's conversation context is not fully restored.**

#### Session Structure
All session files are organized in `~/.claude-swarm/sessions/{project}/{timestamp}/`:
- `config.yml`: Copy of the original swarm configuration
- `state/`: Directory containing individual instance states
  - `{instance_id}.json`: Claude session ID and status for each instance (e.g., `lead_abc123.json`)
- `{instance_name}.mcp.json`: MCP configuration files
- `session.log`: Human-readable request/response tracking
- `session.log.json`: All events in JSONL format (one JSON per line)
# Note: permissions.log is no longer generated as the permission MCP server has been deprecated

#### Listing Sessions
View your previous Claude Swarm sessions:

```bash
# List recent sessions (default: 10)
claude-swarm list-sessions

# List more sessions
claude-swarm list-sessions --limit 20
```

Output shows:
- Session ID (timestamp)
- Creation time
- Main instance name
- Number of instances
- Configuration file used
- Full session path

#### Resuming Sessions
Resume a previous session with all instances restored to their Claude session states:

```bash
# Resume by session ID
claude-swarm --session-id 20250617_143022

# Resume by full path
claude-swarm --session-id ~/.claude-swarm/sessions/my-project/20250617_143022
```

This will:
1. Load the session manifest and instance states
2. Restore the original swarm configuration
3. Resume the main instance with its Claude session ID
4. Restore all connected instances with their session IDs
5. Maintain the same working directories and tool permissions

#### How Session Restoration Works
- Each instance's Claude session ID is automatically captured and persisted
- Instance states are stored in separate files named by instance ID to prevent concurrency issues
- MCP configurations are regenerated with the saved session IDs
- The main instance uses Claude's `--resume` flag (limited effectiveness)
- Connected instances receive their session IDs via `--claude-session-id`

**Important Limitations:**
- The main instance's conversation history and context are not fully restored
- Only the session ID is preserved, not the actual conversation state
- Connected instances restore more reliably than the main instance
- This is an experimental feature and may not work as expected

## How It Works

1. **Configuration Parsing**: Claude Swarm reads your YAML configuration and validates it
2. **MCP Generation**: For each instance, it generates an MCP configuration file that includes:
   - Any explicitly defined MCP servers
   - MCP servers for each connected instance (using `claude-swarm mcp-serve`)
3. **Tool Permissions**: Claude Swarm manages tool permissions through configuration:
   - Each instance's `allowed_tools` specifies which tools it can use
   - Connected instances are accessible via `mcp__<instance_name>__*` pattern
   - Disallowed tools take precedence over allowed tools for fine-grained control
   - Per-instance `vibe: true` skips all permission checks for that specific instance
4. **Session Persistence**: Claude Swarm automatically tracks session state:
   - Generates a shared session path for all instances
   - Each instance's Claude session ID is captured and saved
   - Instance states are stored using instance IDs as filenames to avoid conflicts
   - Sessions can be fully restored with all instances reconnected
5. **Main Instance Launch**: The main instance is launched with its MCP configuration, giving it access to all connected instances
6. **Inter-Instance Communication**: Connected instances expose themselves as MCP servers with these tools:
   - **task**: Execute tasks using Claude Code with configurable tools and return results. The tool description includes the instance name and description (e.g., "Execute a task using Agent frontend_dev. Frontend developer specializing in React and TypeScript")
   - **session_info**: Get current Claude session information including ID and working directory
   - **reset_session**: Reset the Claude session for a fresh start

## Troubleshooting

### Common Issues

**"Configuration file not found"**
- Ensure `claude-swarm.yml` exists in the current directory
- Or specify the path with `--config`

**"Main instance not found in instances"**
- Check that your `main:` field references a valid instance key

**"Unknown instance in connections"**
- Verify all instances in `connections:` arrays are defined

**Permission Errors**
- Ensure Claude CLI is properly installed and accessible
- Check directory permissions for specified paths

### Debug Output

The swarm will display:
- Session directory location (`~/.claude-swarm/sessions/{project}/{timestamp}/`)
- Main instance details (model, directory, tools, connections)
- The exact command being run

### Session Files

Check the session directory `~/.claude-swarm/sessions/{project}/{timestamp}/` for:
- `session.log`: Human-readable logs with request/response tracking
- `session.log.json`: All events in JSONL format (one JSON object per line)
- `{instance}.mcp.json`: MCP configuration for each instance
- All files for a session are kept together for easy review

## Architecture

Claude Swarm consists of these core components:

- **ClaudeSwarm::CLI** (`cli.rb`): Thor-based command-line interface with `start` and `mcp-serve` commands
- **ClaudeSwarm::Configuration** (`configuration.rb`): YAML parser and validator with path expansion
- **ClaudeSwarm::McpGenerator** (`mcp_generator.rb`): Generates MCP JSON configs for each instance
- **ClaudeSwarm::Orchestrator** (`orchestrator.rb`): Launches the main Claude instance with shared session management
- **ClaudeSwarm::ClaudeCodeExecutor** (`claude_code_executor.rb`): Wrapper for executing Claude commands with session persistence
- **ClaudeSwarm::ClaudeMcpServer** (`claude_mcp_server.rb`): FastMCP-based server providing task execution, session info, and reset capabilities

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

### Development Commands

```bash
bin/setup              # Install dependencies
rake test             # Run the Minitest test suite
rake rubocop -A       # Run RuboCop linter with auto-fix
bin/console           # Start IRB session with gem loaded
bundle exec rake install    # Install gem locally
bundle exec rake release    # Release gem to RubyGems.org
rake                  # Default: runs both tests and RuboCop
```

### Release Process

The gem is automatically published to RubyGems when a new release is created on GitHub:

1. Update the version number in `lib/claude_swarm/version.rb`
2. Update `CHANGELOG.md` with the new version's changes
3. Commit the changes: `git commit -am "Bump version to x.y.z"`
4. Create a version tag: `git tag -a vx.y.z -m "Release version x.y.z"`
5. Push the changes and tag: `git push && git push --tags`
6. The GitHub workflow will create a draft release - review and publish it
7. Once published, the gem will be automatically built and pushed to RubyGems

**Note**: You need to set up the `RUBYGEMS_AUTH_TOKEN` secret in your GitHub repository settings with your RubyGems API key.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/parruda/claude-swarm.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).
