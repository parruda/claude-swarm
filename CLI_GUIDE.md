# Swarm CLI Guide

A modern, user-friendly command-line interface for SwarmSDK using TTY toolkit components.

## Installation

```bash
bundle install
```

## Usage

### Basic Command Structure

```bash
swarm run CONFIG_FILE -p "PROMPT" [options]
```

### Options

- `-p, --prompt PROMPT` - Task prompt for the swarm (required unless piped from stdin)
- `--output-format FORMAT` - Output format: 'human' (default) or 'json'
- `-q, --quiet` - Suppress progress output (human format only)
- `-h, --help` - Print help
- `-v, --version` - Print version

## Examples

### 1. Basic Usage

```bash
swarm run examples/simple-swarm-v2.yml -p "Create a REST API for a todo app"
```

### 2. Pipe Prompt from stdin

```bash
echo "Refactor the authentication code" | swarm run team.yml
```

### 3. JSON Output for Scripts

```bash
swarm run team.yml -p "Run tests" --output-format json > output.log
```

### 4. Quiet Mode (Human Format)

```bash
swarm run team.yml -p "Build feature" --quiet
```

## Output Formats

### Human Format (Default)

Beautiful, interactive output with:
- 🐝 **Colored header** with swarm name and lead agent
- 📋 **Prompt display** in a bordered box
- 🔄 **Live spinners** showing agent activity in real-time
- 🤖 **Agent status** with model information
- 🔧 **Tool execution** indicators
- ✓ **Completion status** for each agent
- 📊 **Summary statistics**: tokens, cost, duration, agents involved
- 💬 **Response rendering** with Markdown support

Example output:
```
╔═══════════════════════════════════════════════════════════╗
║  🐝 SwarmSDK - AI Agent Orchestration                     ║
╚═══════════════════════════════════════════════════════════╝

Swarm: Development Team
Lead Agent: developer

Prompt:
┌────────────────────────────────────────────────────────────┐
│ Create a REST API for a todo application                  │
└────────────────────────────────────────────────────────────┘

⠋ Executing swarm...
  ✓ developer completed

────────────────────────────────────────────────────────────────────────────────

✓ Execution Complete

Response:
[Markdown-rendered response here]

Execution Summary:
  🤖 Agents used: developer
  🧠 LLM Requests: 2
  🔧 Tool Calls: 0
  📊 Total Tokens: 1,234
  💰 Total Cost: $0.0012
  ⏱ Duration: 3.45s
```

### JSON Format

Newline-delimited JSON (NDJSON) for programmatic consumption:

```json
{"type":"swarm_start","config_path":"team.yml","swarm_name":"Dev Team","lead_agent":"developer","prompt":"Build API","timestamp":"2025-10-04T10:30:00Z"}
{"type":"llm_request","agent":"developer","model":"gpt-4o-mini","provider":"openai","message_count":1,"tools":[],"timestamp":"2025-10-04T10:30:01Z"}
{"type":"llm_response","agent":"developer","content":"I'll build the API...","usage":{"input_tokens":100,"output_tokens":50,"total_tokens":150,"total_cost":0.0001},"timestamp":"2025-10-04T10:30:03Z"}
{"type":"swarm_complete","status":"success","agent":"developer","content":"API created","duration":3.45,"total_cost":0.0001,"total_tokens":150,"llm_requests":1,"tool_calls":0,"agents_involved":["developer"],"timestamp":"2025-10-04T10:30:04Z"}
```

Each log entry includes:
- `type`: Event type (swarm_start, llm_request, llm_response, tool_call, tool_result, swarm_complete)
- `timestamp`: ISO 8601 timestamp
- Event-specific data fields

## Configuration Format

SwarmCLI uses SwarmSDK version 2 configuration format:

```yaml
version: 2
swarm:
  name: "My Development Team"
  lead: lead_agent
  agents:
    lead_agent:
      description: "Lead developer"
      model: gpt-4o-mini
      system_prompt: |
        You are a lead developer...
      tools: []
      delegates_to: []
      directories: ["."]
```

See SwarmSDK documentation for full configuration reference.

## Exit Codes

- `0` - Success
- `1` - Error (configuration, execution, or general error)
- `130` - User cancelled (Ctrl+C)

## Advanced Usage

### Environment Variables

SwarmSDK respects standard LLM provider environment variables:
- `OPENAI_API_KEY` - OpenAI API key
- `ANTHROPIC_API_KEY` - Anthropic API key
- etc. (see RubyLLM documentation)

### Piping and Scripting

The JSON output format is designed for scripting:

```bash
# Filter for errors
swarm run team.yml -p "Task" --output-format json | jq 'select(.type == "error")'

# Extract total cost
swarm run team.yml -p "Task" --output-format json | jq 'select(.type == "swarm_complete") | .total_cost'

# Monitor in real-time
swarm run team.yml -p "Long task" --output-format json | while read line; do
  echo "$line" | jq -r '.type + ": " + (.agent // "N/A")'
done
```

## Architecture

The CLI is organized into separate concerns:

- **lib/swarm_cli/cli.rb** - Main CLI entry point and command routing
- **lib/swarm_cli/options.rb** - Command-line option parsing (TTY::Option)
- **lib/swarm_cli/commands/run.rb** - Run command implementation
- **lib/swarm_cli/formatters/human_formatter.rb** - Beautiful terminal output
- **lib/swarm_cli/formatters/json_formatter.rb** - Structured JSON logging

This modular design makes it easy to add new commands and output formats in the future.

## Future: Interactive Mode

The current implementation is non-interactive. Future versions will support:
- Interactive prompts during execution (TTY::Prompt)
- Real-time user interaction with the lead agent
- Dynamic task refinement
- Progress monitoring with user controls

The reusable formatter design ensures smooth transition to interactive mode.
