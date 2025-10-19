# SwarmCLI Command Reference

Complete command-line interface reference for SwarmCLI v2.

---

## Global Options

Available for all commands:

### `--help`, `-h`

Display help information for the command.

**Type:** Flag
**Default:** N/A

```bash
swarm --help
swarm run --help
swarm mcp serve --help
```

### `--version`, `-v`

Display SwarmCLI version number.

**Type:** Flag
**Default:** N/A

```bash
swarm --version
```

---

## swarm run

Execute a swarm with AI agents.

### Synopsis

```bash
swarm run CONFIG_FILE [PROMPT_TEXT] [OPTIONS]
swarm run CONFIG_FILE -p PROMPT [OPTIONS]
echo "PROMPT" | swarm run CONFIG_FILE
echo "PROMPT" | swarm run CONFIG_FILE -p
```

### Description

Runs a swarm of AI agents defined in a YAML or Ruby DSL configuration file. Supports two modes:

1. **Interactive REPL mode** (default): Opens an interactive session where you can chat with the swarm
2. **Non-interactive mode** (`-p` flag): Executes a single prompt and exits

### Arguments

#### CONFIG_FILE

**Type:** String (required)
**Description:** Path to swarm configuration file
**Formats:** `.yml`, `.yaml` (YAML) or `.rb` (Ruby DSL)

**Examples:**
```bash
swarm run team.yml
swarm run config/swarm.rb
```

#### PROMPT_TEXT

**Type:** String (optional)
**Description:** Initial message for REPL mode or task prompt for non-interactive mode
**Usage:**
- Without `-p` flag: Opens REPL with this as first message
- With `-p` flag: Runs prompt non-interactively and exits

**Examples:**
```bash
# REPL with initial message
swarm run team.yml "Build a REST API"

# Non-interactive execution
swarm run team.yml -p "Build a REST API"
```

### Options

#### `--prompt`, `-p`

Run in non-interactive mode. When specified, executes a single prompt and exits instead of opening a REPL.

**Type:** Flag
**Default:** `false` (REPL mode)
**Prompt source:** Reads from PROMPT_TEXT argument or stdin

**Examples:**
```bash
# From argument
swarm run team.yml -p "Build a REST API"

# From stdin
echo "Build a REST API" | swarm run team.yml -p
```

#### `--output-format FORMAT`

Output format for results.

**Type:** String
**Values:** `human`, `json`
**Default:** `human`

**Human format:**
- Pretty-printed, colorized output
- Progress indicators and spinners
- Agent badges and visual structure
- Best for terminal viewing

**JSON format:**
- Structured JSON events on stdout
- One JSON object per line
- Suitable for programmatic consumption
- Includes all event types: `swarm_start`, `user_prompt`, `agent_step`, `tool_call`, `tool_result`, `agent_stop`, `swarm_stop`

**Examples:**
```bash
# Human-readable output (default)
swarm run team.yml -p "Build API"

# JSON output for parsing
swarm run team.yml -p "Build API" --output-format json
swarm run team.yml -p "Build API" --output-format json | jq '.type'
```

#### `--quiet`, `-q`

Suppress progress output in human format. Only affects human output; ignored in JSON mode.

**Type:** Flag
**Default:** `false`
**Applies to:** Human format only

**Examples:**
```bash
swarm run team.yml -p "Build API" --quiet
swarm run team.yml -p "Build API" -q
```

#### `--truncate`

Truncate long outputs for concise view in human format.

**Type:** Flag
**Default:** `false`
**Applies to:** Human format only

**Examples:**
```bash
swarm run team.yml -p "Build API" --truncate
```

#### `--verbose`

Show system reminders and additional debug information in human format.

**Type:** Flag
**Default:** `false`
**Applies to:** Human format only

**Examples:**
```bash
swarm run team.yml -p "Build API" --verbose
```

### Examples

```bash
# Interactive REPL mode
swarm run team.yml

# REPL with initial message
swarm run team.yml "Build a REST API"

# REPL with piped initial message
echo "Build a REST API" | swarm run team.yml

# Non-interactive execution from argument
swarm run team.yml -p "Build a REST API"

# Non-interactive from stdin
echo "Build a REST API" | swarm run team.yml -p

# JSON output for parsing
swarm run team.yml -p "Refactor code" --output-format json

# Quiet mode
swarm run team.yml -p "Build API" --quiet

# Verbose debugging
swarm run team.yml -p "Build API" --verbose

# Truncated output
swarm run team.yml -p "Build API" --truncate
```

### Exit Codes

- **0**: Success
- **1**: Error (configuration error, execution error, etc.)
- **130**: Interrupted (Ctrl+C)

---

## swarm migrate

Migrate Claude Swarm v1 configurations to SwarmSDK v2 format.

### Synopsis

```bash
swarm migrate INPUT_FILE [--output OUTPUT_FILE]
```

### Description

Converts a Claude Swarm v1 YAML configuration to the new SwarmSDK v2 format. The migrated configuration is written to a file or stdout.

### Arguments

#### INPUT_FILE

**Type:** String (required)
**Description:** Path to Claude Swarm v1 configuration file

**Examples:**
```bash
swarm migrate old-config.yml
swarm migrate config/v1-swarm.yml
```

### Options

#### `--output FILE`, `-o FILE`

Output file path for migrated configuration.

**Type:** String
**Default:** stdout
**Behavior:**
- If specified: Writes to file and prints success message to stderr
- If omitted: Prints migrated YAML to stdout

**Examples:**
```bash
# Output to file
swarm migrate old-config.yml --output new-config.yml
swarm migrate old-config.yml -o new-config.yml

# Output to stdout (redirect as needed)
swarm migrate old-config.yml > new-config.yml
swarm migrate old-config.yml | tee new-config.yml
```

### Examples

```bash
# Print to stdout
swarm migrate old-config.yml

# Save to file
swarm migrate old-config.yml --output new-config.yml

# Short form
swarm migrate old-config.yml -o new-config.yml

# Pipe and review
swarm migrate old-config.yml | less
```

### Exit Codes

- **0**: Success
- **1**: Error (file not found, invalid YAML, etc.)
- **130**: Interrupted (Ctrl+C)

---

## swarm mcp serve

Start an MCP server exposing the swarm's lead agent as a tool.

### Synopsis

```bash
swarm mcp serve CONFIG_FILE
```

### Description

Starts an MCP (Model Context Protocol) server that exposes the swarm's lead agent as a tool named `task`. The server uses stdio transport and can be integrated with other AI systems.

The exposed tool accepts:
- **task** (required): The task or prompt to execute
- **description** (optional): Brief description of the task
- **thinking_budget** (optional): Thinking budget level (`think`, `think hard`, `think harder`, `ultrathink`)

### Arguments

#### CONFIG_FILE

**Type:** String (required)
**Description:** Path to swarm configuration file (YAML or Ruby DSL)

**Examples:**
```bash
swarm mcp serve team.yml
swarm mcp serve config/swarm.rb
```

### Options

None beyond global `--help`.

### Examples

```bash
# Start MCP server
swarm mcp serve team.yml

# Use in Claude Desktop configuration
# Add to claude_desktop_config.json:
{
  "mcpServers": {
    "swarm": {
      "command": "swarm",
      "args": ["mcp", "serve", "/path/to/team.yml"]
    }
  }
}
```

### MCP Tool Schema

**Tool name:** `task`

**Parameters:**
- `task` (string, required): The task or prompt to execute
- `description` (string, optional): Brief description of the task
- `thinking_budget` (string, optional): One of `think`, `think hard`, `think harder`, `ultrathink`

**Response:**
- On success: Returns the swarm's response content as a string
- On failure: Returns a JSON object with `success: false` and error details

### Exit Codes

- **0**: Success
- **1**: Error (configuration error, server startup error)
- **130**: Interrupted (Ctrl+C)

---

## swarm mcp tools

Start an MCP server exposing SwarmSDK tools.

### Synopsis

```bash
swarm mcp tools [TOOL_NAMES...]
```

### Description

Starts an MCP server that exposes SwarmSDK tools (Read, Write, Edit, Bash, Grep, Glob, etc.) for use in other AI systems. Tools can be space-separated or comma-separated.

### Arguments

#### TOOL_NAMES

**Type:** String (optional, variadic)
**Default:** All available tools
**Format:** Space-separated or comma-separated tool names

**Available tools:**
- `Read`: Read files
- `Write`: Write files
- `Edit`: Edit files with find/replace
- `MultiEdit`: Edit multiple files
- `Bash`: Execute bash commands
- `Grep`: Search file contents (ripgrep)
- `Glob`: Find files by pattern
- `TodoWrite`: Manage task lists
- `Think`: Extended reasoning
- `WebFetch`: Fetch and process web content
- `ScratchpadWrite`: Write to shared scratchpad (volatile)
- `ScratchpadRead`: Read from shared scratchpad
- `ScratchpadList`: List scratchpad entries
- `MemoryWrite`: Write to per-agent memory (persistent)
- `MemoryRead`: Read from memory (with line numbers)
- `MemoryEdit`: Edit memory entries
- `MemoryMultiEdit`: Apply multiple edits to memory
- `MemoryGlob`: Search memory by glob pattern
- `MemoryGrep`: Search memory content by regex
- `MemoryDelete`: Delete memory entries

**Examples:**
```bash
# All tools
swarm mcp tools

# Specific tools (space-separated)
swarm mcp tools Read Write Bash

# Specific tools (comma-separated)
swarm mcp tools Read,Write,Bash

# Mixed format
swarm mcp tools Read Write,Edit Bash
```

### Options

None beyond global `--help`.

### Examples

```bash
# Expose all tools
swarm mcp tools

# Expose file operations only
swarm mcp tools Read Write Edit

# Expose search tools
swarm mcp tools Grep Glob

# Expose scratchpad tools
swarm mcp tools ScratchpadWrite ScratchpadRead ScratchpadEdit ScratchpadMultiEdit ScratchpadGlob ScratchpadGrep

# Use in Claude Desktop configuration
{
  "mcpServers": {
    "swarm-tools": {
      "command": "swarm",
      "args": ["mcp", "tools", "Read", "Write", "Bash"]
    }
  }
}
```

### Exit Codes

- **0**: Success
- **1**: Error (invalid tool name, server startup error)
- **130**: Interrupted (Ctrl+C)

---

## Output Formats

### Human Format

The default output format provides a rich, terminal-friendly experience:

**Features:**
- Colorized agent badges
- Progress spinners during execution
- Pretty-printed tool calls and results
- Usage statistics (tokens, cost, duration)
- Visual hierarchy with borders and spacing

**Flags:**
- `--quiet`: Suppress progress indicators
- `--truncate`: Truncate long outputs
- `--verbose`: Show system reminders and debug info

**Example output:**
```
🚀 Swarm starting: Development Team
   Lead agent: backend

👤 backend • gpt-5 • openai
   Message 1 of 1 • 3 tools • Delegates to: frontend

🔧 Read { file_path: "src/app.js" }
   ✓ Read 142 lines

💬 backend
   Here is the code analysis...

✅ Execution complete in 3.2s
   Cost: $0.0045 • Tokens: 1,234
   Agents: backend, frontend
```

### JSON Format

Structured event stream for programmatic consumption. Each line is a JSON object with a `type` field.

**Event types:**

#### `swarm_start`
```json
{
  "type": "swarm_start",
  "swarm_name": "Development Team",
  "lead_agent": "backend",
  "prompt": "Build a REST API",
  "timestamp": "2024-01-01T12:00:00Z"
}
```

#### `user_prompt`
```json
{
  "type": "user_prompt",
  "agent": "backend",
  "model": "gpt-5",
  "provider": "openai",
  "message_count": 1,
  "tools": ["Read", "Write", "Bash"],
  "delegates_to": ["frontend"]
}
```

#### `agent_step`
```json
{
  "type": "agent_step",
  "agent": "backend",
  "model": "gpt-5",
  "content": "I'll read the file",
  "tool_calls": [
    {
      "id": "call_123",
      "name": "Read",
      "arguments": { "file_path": "src/app.js" }
    }
  ],
  "finish_reason": "tool_calls",
  "usage": {
    "input_tokens": 234,
    "output_tokens": 56,
    "total_tokens": 290,
    "input_cost": 0.00117,
    "output_cost": 0.00084,
    "total_cost": 0.00201
  }
}
```

#### `tool_call`
```json
{
  "type": "tool_call",
  "agent": "backend",
  "tool_call_id": "call_123",
  "tool": "Read",
  "arguments": { "file_path": "src/app.js" }
}
```

#### `tool_result`
```json
{
  "type": "tool_result",
  "agent": "backend",
  "tool_call_id": "call_123",
  "tool": "Read",
  "result": "File contents..."
}
```

#### `agent_stop`
```json
{
  "type": "agent_stop",
  "agent": "backend",
  "model": "gpt-5",
  "content": "Here is the analysis",
  "finish_reason": "stop",
  "usage": { ... }
}
```

#### `swarm_stop`
```json
{
  "type": "swarm_stop",
  "swarm_name": "Development Team",
  "lead_agent": "backend",
  "last_agent": "backend",
  "content": "Analysis complete",
  "success": true,
  "duration": 3.2,
  "total_cost": 0.0045,
  "total_tokens": 1234,
  "agents_involved": ["backend", "frontend"],
  "timestamp": "2024-01-01T12:00:03Z"
}
```

---

## Configuration Files

SwarmCLI accepts two configuration formats:

### YAML Configuration

```yaml
version: 2
swarm:
  name: "Development Team"
  lead: backend
  agents:
    backend:
      description: "Backend developer"
      model: gpt-5
      tools: [Read, Write, Bash]
```

See [YAML Reference](./yaml.md) for complete documentation.

### Ruby DSL Configuration

```ruby
SwarmSDK.build do
  name "Development Team"
  lead :backend

  agent :backend do
    model "gpt-5"
    description "Backend developer"
    tools :Read, :Write, :Bash
  end
end
```

See [Ruby DSL Reference](./ruby-dsl.md) for complete documentation.

---

## Environment Variables

SwarmCLI respects the following environment variables:

### LLM Provider API Keys

**OpenAI:**
- `OPENAI_API_KEY`: OpenAI API key
- `OPENAI_BASE_URL`: Custom OpenAI API endpoint

**Anthropic:**
- `ANTHROPIC_API_KEY`: Anthropic API key

**Google:**
- `GOOGLE_API_KEY`: Google AI API key

**Other providers:** See RubyLLM documentation for provider-specific variables.

### Debug

- `DEBUG=1`: Enable debug logging (MCP clients, internal operations)

---

## Common Workflows

### Development Workflow

```bash
# 1. Create configuration
cat > team.yml <<EOF
version: 2
swarm:
  name: "Dev Team"
  lead: developer
  agents:
    developer:
      description: "Software developer"
      model: gpt-5
      tools: [Read, Write, Edit, Bash]
EOF

# 2. Test interactively
swarm run team.yml

# 3. Test non-interactively
swarm run team.yml -p "Add error handling to app.js"

# 4. Use JSON output for automation
swarm run team.yml -p "Run tests" --output-format json | jq
```

### CI/CD Integration

```bash
# Run swarm task and check exit code
swarm run ci-swarm.yml -p "Run linter and tests" --quiet
if [ $? -eq 0 ]; then
  echo "All checks passed"
else
  echo "Checks failed"
  exit 1
fi
```

### MCP Server Setup

```bash
# Start swarm as MCP server (daemonize or run in tmux/screen)
swarm mcp serve team.yml

# Or expose just tools
swarm mcp tools Read Write Bash
```

---

## See Also

- [YAML Reference](./yaml.md): Complete YAML configuration reference
- [Ruby DSL Reference](./ruby-dsl.md): Complete Ruby DSL reference
- [Getting Started Guide](../guides/getting-started.md): Introduction to SwarmSDK
- [Quick Start CLI](../guides/quick-start-cli.md): Quick CLI examples
