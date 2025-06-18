# Claude Swarm

[![Gem Version](https://badge.fury.io/rb/claude_swarm.svg?cache_bust=0.1.17)](https://badge.fury.io/rb/claude_swarm)
[![CI](https://github.com/parruda/claude-swarm/actions/workflows/ci.yml/badge.svg)](https://github.com/parruda/claude-swarm/actions/workflows/ci.yml)

Claude Swarm orchestrates multiple Claude Code instances as a collaborative AI development team. It enables running AI agents with specialized roles, tools, and directory contexts, communicating via MCP (Model Context Protocol) in a tree-like hierarchy. Define your swarm topology in simple YAML and let Claude instances delegate tasks through connected instances. Perfect for complex projects requiring specialized AI agents for frontend, backend, testing, DevOps, or research tasks.

## Installation

Install the gem by executing:

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

1. Run `claude-swarm init` or create a `claude-swarm.yml` file in your project:

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
  instances:
    # Instance definitions...
```

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

# Watch live logs from most recent session
claude-swarm watch 

# Watch logs starting from the last 50 lines
claude-swarm watch 20250617_235233 -n 50

# List all available sessions (including completed ones)
claude-swarm list-sessions
claude-swarm list-sessions --limit 20

# Clean up stale session symlinks
claude-swarm clean

# Remove sessions older than 30 days
claude-swarm clean --days 30
```

Example output from `claude-swarm ps`:
```
⚠️  Total cost does not include the cost of the main instance

SESSION_ID       SWARM_NAME                 TOTAL_COST    UPTIME      DIRECTORY
-------------------------------------------------------------------------------
20250617_235233  Feature Development        $0.3847       15m         .
20250617_143022  Bug Investigation          $1.2156       1h          ./shopify
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

*Note: permissions.log is no longer generated as the permission MCP server has been deprecated*

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
