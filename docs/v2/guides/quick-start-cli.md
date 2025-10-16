# Getting Started with SwarmCLI

## What You'll Learn

- What SwarmCLI is and when to use it
- How to install and verify SwarmCLI (separate from SwarmSDK)
- The two execution modes: interactive (REPL) and non-interactive
- Available commands and their purposes
- How to use the interactive REPL for conversations
- How to use non-interactive mode with NDJSON streaming for automation
- Working with configuration files (YAML and Ruby DSL)
- Common workflows and real-world examples
- How to parse NDJSON output correctly (not single JSON objects)

## Prerequisites

- **Ruby 3.2.0 or higher** installed on your system
- **LLM API access** - an API key for OpenAI, Anthropic, or another provider
- **A swarm configuration file** - either YAML or Ruby DSL (see [Getting Started with SwarmSDK](getting-started.md))
- **10-15 minutes** to complete this guide

## What is SwarmCLI?

SwarmCLI is a command-line interface for running SwarmSDK swarms. It's a **separate gem** (`swarm_cli`) that depends on and extends `swarm_sdk`. Installing `swarm_cli` automatically installs `swarm_sdk` as a dependency.

**Two separate gems**:
- **`swarm_sdk`** - The core library for building agent swarms
- **`swarm_cli`** - The CLI tool for running swarms from the terminal

SwarmCLI provides two ways to interact with your AI agent teams:

**Interactive Mode (REPL)**: A conversational interface where you chat with your swarm in real-time. Perfect for:
- Exploratory work and experimentation
- Iterative development with feedback loops
- Learning how your agents collaborate
- Long conversations with context preservation

**Non-Interactive Mode**: One-shot task execution with immediate results and NDJSON streaming. Perfect for:
- Automation and scripting
- CI/CD pipelines
- Batch processing
- Real-time monitoring and cost tracking
- Scheduled tasks

**Why use SwarmCLI?** Instead of writing Ruby code to execute your swarms, you can simply run `swarm run config.yml` and start working. It's faster for quick tasks and provides a polished terminal experience with structured JSON output for automation.

## Installation

Install the SwarmCLI gem (which automatically installs SwarmSDK as a dependency):

```bash
gem install swarm_cli
```

**What gets installed**:
- `swarm_cli` gem (the CLI tool)
- `swarm_sdk` gem (automatically as a dependency)
- `swarm` executable (the command you'll use)

Or add to your Gemfile:

```ruby
gem 'swarm_cli'  # This will also install swarm_sdk as a dependency
```

Then install:

```bash
bundle install
```

**Important notes**:
- `swarm_cli` and `swarm_sdk` are **separate gems**
- Installing `swarm_cli` automatically installs `swarm_sdk`
- The executable is called `swarm` (NOT `swarm_cli`)
- Requires Ruby 3.2.0 or higher

### Verify Installation

Check that SwarmCLI is installed correctly:

```bash
swarm --version
```

**Expected output**:
```
SwarmCLI v2.0.0
```

Check Ruby version:

```bash
ruby -v
```

**Expected output**:
```
ruby 3.2.0 (or higher)
```

Get help on available commands:

```bash
swarm --help
```

**Expected output**:
```
SwarmCLI v2.0.0 - AI Agent Orchestration

Usage:
  swarm run CONFIG_FILE -p PROMPT [options]
  swarm migrate INPUT_FILE [--output OUTPUT_FILE]
  swarm mcp serve CONFIG_FILE
  swarm mcp tools [TOOL_NAMES...]

Commands:
  run           Execute a swarm with AI agents
  migrate       Migrate Claude Swarm v1 config to SwarmSDK v2 format
  mcp serve     Start an MCP server exposing swarm lead agent
  mcp tools     Start an MCP server exposing SwarmSDK tools

Options:
  -p, --prompt PROMPT          Task prompt for the swarm
  -o, --output FILE            Output file for migrated config (default: stdout)
  --output-format FORMAT       Output format: 'human' or 'json' (default: human)
  -q, --quiet                  Suppress progress output (human format only)
  --truncate                   Truncate long outputs for concise view
  --verbose                    Show system reminders and additional debug information
  -h, --help                   Print help
  -v, --version                Print version
```

## Quick Start: Your First Command

Let's create a simple swarm configuration and run it.

### Step 1: Create a Configuration File

Create a file called `assistant.yml`:

```yaml
version: 2
swarm:
  name: "Quick Start Assistant"
  lead: helper

  agents:
    helper:
      description: "A helpful assistant"
      model: "gpt-4"
      system_prompt: |
        You are a helpful assistant.
        Answer questions clearly and concisely.
      tools:
        - Write
```

### Step 2: Set Your API Key

Ensure your API key is set:

```bash
export OPENAI_API_KEY="sk-your-key-here"
```

Or create a `.env` file:

```bash
echo "OPENAI_API_KEY=sk-your-key-here" > .env
```

### Step 3: Run Interactive Mode

Start a conversation with your swarm:

```bash
swarm run assistant.yml
```

**Expected output**:
```
────────────────────────────────────────────────────────────
🚀 Swarm CLI Interactive REPL
────────────────────────────────────────────────────────────

Swarm: Quick Start Assistant
Lead Agent: helper

Type your message and press Enter to submit
Type /help for commands or /exit to quit

────────────────────────────────────────────────────────────

You ❯
```

**Try it**: Type "What is 2 + 2?" and press Enter.

The swarm will process your question and respond. Continue the conversation by typing more messages.

### Step 4: Exit the REPL

Type `/exit` or press `Ctrl+D` to exit.

**Expected output**:
```
👋 Goodbye! Thanks for using Swarm CLI

────────────────────────────────────────────────────────────
📊 Session Summary
────────────────────────────────────────────────────────────

  Messages sent: 1
  Agents used: helper
  LLM Requests: 1
  Tool Calls: 0
  Total Tokens: 245
  Total Cost: $0.0012
  Session Duration: 1.23s

────────────────────────────────────────────────────────────
```

Congratulations! You've successfully run your first SwarmCLI command.

## Commands Overview

SwarmCLI provides four main commands:

### 1. swarm run

Execute a swarm with your agents. Supports both interactive and non-interactive modes.

**Interactive mode (REPL)**:
```bash
swarm run config.yml
```

**Non-interactive mode**:
```bash
swarm run config.yml -p "Your task here"
```

**Key options**:
- `-p, --prompt PROMPT` - Enable non-interactive mode with a prompt
- `--output-format FORMAT` - Choose output format: `human` (default) or `json` (NDJSON)
- `-q, --quiet` - Suppress progress output
- `--truncate` - Truncate long outputs for concise view
- `--verbose` - Show additional debug information

### 2. swarm migrate

Convert old Claude Swarm v1 configurations to SwarmSDK v2 format.

```bash
swarm migrate old-config.yml
swarm migrate old-config.yml --output new-config.yml
```

**Use case**: Upgrading from version 1 to version 2.

### 3. swarm mcp serve

Start an MCP (Model Context Protocol) server that exposes your swarm as a tool.

```bash
swarm mcp serve config.yml
```

**Use case**: Integrating your swarm with MCP-compatible tools and frameworks.

### 4. swarm mcp tools

Start an MCP server that exposes SwarmSDK's built-in tools.

```bash
# Expose all tools
swarm mcp tools

# Expose specific tools
swarm mcp tools Bash Grep Read

# Comma-separated (no spaces)
swarm mcp tools Read,Write,Edit
```

**Use case**: Making SwarmSDK tools available to other MCP clients.

## Interactive Mode (REPL)

The interactive REPL provides a conversational interface for working with your swarm.

### Starting the REPL

**Basic usage**:
```bash
swarm run config.yml
```

**With an initial message**:
```bash
swarm run config.yml "Start by analyzing the README.md file"
```

**With piped input**:
```bash
echo "Summarize the main.rb file" | swarm run config.yml
```

In all three cases above, you'll enter interactive mode, but the last two will send an initial message before the first prompt.

### Understanding the Interface

Once in the REPL, you'll see:

```
────────────────────────────────────────────────────────────
🚀 Swarm CLI Interactive REPL
────────────────────────────────────────────────────────────

Swarm: Development Team
Lead Agent: architect

Type your message and press Enter to submit
Type /help for commands or /exit to quit

────────────────────────────────────────────────────────────

You ❯
```

**What you're seeing**:
1. **Header** - Welcome banner with swarm information
2. **Swarm name and lead agent** - Shows which swarm and agent you're talking to
3. **Instructions** - How to use the REPL
4. **Prompt** - `You ❯` indicates you can type your message

### Conversation Flow

**1. Type your message and press Enter**:
```
You ❯ What files are in this directory?
```

**2. The swarm processes your request**:
```
architect • thinking...
```

**3. The agent responds**:
```
architect:
Based on the directory listing, here are the files:
- README.md
- src/main.rb
- src/config.yml
- tests/test_main.rb
```

**4. Context stats appear before next prompt**:
```
[architect • 1 msg • 245 tokens • $0.0012 • 15% context]
You ❯
```

These stats show:
- **Agent name**: Which agent you're talking to
- **Message count**: Number of messages sent
- **Token usage**: Total tokens consumed
- **Cost**: Total cost in USD
- **Context usage**: Percentage of context window used (color-coded: green < 50%, yellow < 80%, red ≥ 80%)

### REPL Commands

Type `/help` to see available commands:

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/clear` | Clear the screen |
| `/history` | Show conversation history |
| `/exit` | Exit the REPL (or press Ctrl+D) |

**Using commands**:

```
You ❯ /help
```

Shows a help box with all commands and input tips.

```
You ❯ /history
```

Shows your entire conversation with truncated long messages.

```
You ❯ /clear
```

Clears the screen and shows the welcome banner again.

```
You ❯ /exit
```

Exits the REPL and shows a session summary.

### Tab Completion

The REPL provides intelligent tab completion:

**Command completion**: Type `/` and press Tab to see available commands:
```
You ❯ /
/help    /clear    /history    /exit
```

**File path completion**: Type `@` followed by a partial path and press Tab:
```
You ❯ Read @src/m
@src/main.rb    @src/models/    @src/modules/
```

**Navigation**:
- Press `Tab` to cycle forward through completions
- Press `Shift+Tab` to cycle backward
- Press `Enter` to accept the selected completion

### Context Preservation

The REPL maintains conversation context across messages:

```
You ❯ What files are in src/?

architect:
The src/ directory contains:
- main.rb
- config.yml
- utils.rb

You ❯ What does the first one do?

architect:
main.rb is the entry point. It loads the configuration and starts the application.
```

Notice how the second question ("What does the first one do?") references the previous response. The agent understands you're asking about `main.rb` because the conversation context is preserved.

### Session Summary

When you exit (via `/exit` or `Ctrl+D`), you'll see a summary:

```
────────────────────────────────────────────────────────────
📊 Session Summary
────────────────────────────────────────────────────────────

  Messages sent: 5
  Agents used: architect, coder, reviewer
  LLM Requests: 8
  Tool Calls: 12
  Total Tokens: 1.2K
  Total Cost: $0.0156
  Session Duration: 2m 34s

────────────────────────────────────────────────────────────
```

This shows:
- **Messages sent**: Number of user messages
- **Agents used**: Which agents participated
- **LLM Requests**: Total API calls made
- **Tool Calls**: Total tool invocations
- **Tokens and cost**: Session totals
- **Duration**: Total time in the REPL

## Non-Interactive Mode

Non-interactive mode executes a single task and exits. Perfect for scripting and automation with structured NDJSON output.

### Basic Usage

**Provide prompt as argument**:
```bash
swarm run config.yml -p "Build a REST API for user management"
```

**Provide prompt via stdin**:
```bash
echo "Build a REST API for user management" | swarm run config.yml -p
```

**Use a heredoc for long prompts**:
```bash
swarm run config.yml -p "$(cat <<'EOF'
Build a REST API with the following features:
1. User registration and authentication
2. CRUD operations for user profiles
3. JWT token-based authorization
4. Input validation and error handling
EOF
)"
```

### Understanding Output Formats

SwarmCLI supports two output formats: `human` (default) and `json` (NDJSON).

### Human Format (Default)

**Example**:
```bash
swarm run config.yml -p "What is 2 + 2?"
```

**Output**:
```
Swarm: Quick Start Assistant
Lead Agent: helper
Task: What is 2 + 2?
────────────────────────────────────────────────────────────

helper • thinking...

helper:
The answer is 4.

────────────────────────────────────────────────────────────
✓ Success
Duration: 1.23s • Cost: $0.0012 • Tokens: 245
────────────────────────────────────────────────────────────
```

The human format provides:
- **Header**: Swarm info and task
- **Progress indicators**: Shows what's happening
- **Agent responses**: Formatted and colored
- **Summary**: Duration, cost, and token usage

### JSON Output Format (NDJSON Event Stream)

**CRITICAL**: JSON output is **NDJSON** (newline-delimited JSON), not a single JSON object.

For scripting and automation, use JSON format which outputs **newline-delimited JSON (NDJSON)** - one event per line:

```bash
swarm run config.yml -p "What is 2 + 2?" --output-format json
```

**Output** (NDJSON - each line is a separate JSON event):
```json
{"type":"swarm_start","swarm_name":"Quick Start Assistant","lead_agent":"helper","prompt":"What is 2 + 2?","timestamp":"2024-01-15T10:30:00Z"}
{"type":"user_prompt","agent":"helper","model":"gpt-4","message_count":0,"timestamp":"2024-01-15T10:30:00Z"}
{"type":"agent_step","agent":"helper","model":"gpt-4","content":"","tool_calls":[{"id":"call_123","name":"think","arguments":{}}],"usage":{"prompt_tokens":50,"completion_tokens":10,"total_tokens":60,"cost":0.0003},"timestamp":"2024-01-15T10:30:01Z"}
{"type":"agent_stop","agent":"helper","model":"gpt-4","content":"The answer is 4.","tool_calls":[],"finish_reason":"stop","usage":{"prompt_tokens":60,"completion_tokens":5,"total_tokens":65,"cost":0.0003},"timestamp":"2024-01-15T10:30:02Z"}
{"type":"swarm_stop","swarm_name":"Quick Start Assistant","lead_agent":"helper","success":true,"duration":1.23,"total_cost":0.0012,"total_tokens":245,"agents_involved":["helper"],"timestamp":"2024-01-15T10:30:02Z"}
```

**CRITICAL UNDERSTANDING - NDJSON vs Regular JSON**:

❌ **NOT a single JSON object**:
```json
{
  "events": [
    {"type": "swarm_start", ...},
    {"type": "agent_stop", ...}
  ]
}
```

✅ **NDJSON - one event per line**:
```
{"type":"swarm_start",...}
{"type":"agent_step",...}
{"type":"agent_stop",...}
{"type":"swarm_stop",...}
```

### Why NDJSON?

**Key benefits**:
1. **Real-time streaming**: Events arrive as they happen (not buffered until completion)
2. **Line-by-line processing**: Easy to process incrementally with standard tools
3. **Memory efficient**: No need to load entire response into memory
4. **Tool friendly**: Works perfectly with `jq`, `grep`, `awk`, etc.
5. **Fault tolerant**: Partial results available even if process crashes

### NDJSON Event Types

Each line in NDJSON output is one of these event types:

| Event Type | Description | Key Fields |
|------------|-------------|------------|
| `swarm_start` | Swarm execution begins | `swarm_name`, `lead_agent`, `prompt` |
| `user_prompt` | User message sent to agent | `agent`, `model`, `message_count` |
| `agent_step` | Agent produces intermediate output | `agent`, `content`, `tool_calls`, `usage` |
| `agent_stop` | Agent completes its response | `agent`, `content`, `finish_reason`, `usage` |
| `tool_call` | Agent invokes a tool | `tool`, `arguments`, `tool_call_id` |
| `tool_result` | Tool returns result | `tool`, `result`, `tool_call_id` |
| `agent_delegation` | Agent delegates to another agent | `agent`, `delegate_to`, `tool_call_id` |
| `delegation_result` | Delegated agent completes | `agent`, `delegate_from`, `result` |
| `delegation_error` | Delegation fails | `agent`, `delegate_to`, `error_message` |
| `node_start` | Node execution begins (workflows) | `node_name`, `lead_agent` |
| `node_stop` | Node execution completes (workflows) | `node_name`, `success`, `duration` |
| `model_lookup_warning` | Unknown model in config | `agent`, `model`, `suggestions` |
| `context_limit_warning` | Context usage threshold crossed | `agent`, `threshold`, `current_usage` |
| `swarm_stop` | Swarm execution completes | `success`, `duration`, `total_cost`, `agents_involved` |

### Processing NDJSON with jq

`jq` is the standard tool for processing JSON. Here's how to work with NDJSON:

**Extract all agent responses**:
```bash
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "agent_stop") | .content'
```

**Output**:
```
"Here is the first response."
"Here is the second response."
```

**Calculate total cost from events**:
```bash
swarm run config.yml -p "Task" --output-format json | \
  jq -s '[.[] | select(.usage) | .usage.cost] | add'
```

**Output**:
```
0.0156
```

**Get final success status**:
```bash
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "swarm_stop") | .success'
```

**Output**:
```
true
```

**Extract just the final content**:
```bash
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "agent_stop") | .content' | tail -1
```

**Output**:
```
"The answer is 4."
```

**Track costs in real-time**:
```bash
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.usage) | {agent, cost: .usage.cost}'
```

**Output** (streaming as events arrive):
```
{"agent":"helper","cost":0.0003}
{"agent":"helper","cost":0.0003}
{"agent":"helper","cost":0.0006}
```

**Filter tool calls**:
```bash
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "tool_call") | {tool, arguments}'
```

**Get all agents involved**:
```bash
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "swarm_stop") | .agents_involved'
```

**Output**:
```
["architect","coder","reviewer"]
```

### Processing NDJSON in Bash Scripts

**Real-time event processing**:
```bash
#!/bin/bash
# process-events.sh - Process NDJSON events as they arrive

swarm run config.yml -p "Task" --output-format json | while IFS= read -r event; do
  type=$(echo "$event" | jq -r '.type')

  case $type in
    swarm_start)
      swarm_name=$(echo "$event" | jq -r '.swarm_name')
      echo "🚀 Starting swarm: $swarm_name"
      ;;
    agent_step)
      agent=$(echo "$event" | jq -r '.agent')
      cost=$(echo "$event" | jq -r '.usage.cost')
      echo "💭 $agent thinking (cost: \$$cost)"
      ;;
    tool_call)
      tool=$(echo "$event" | jq -r '.tool')
      echo "🔧 Calling tool: $tool"
      ;;
    agent_stop)
      agent=$(echo "$event" | jq -r '.agent')
      content=$(echo "$event" | jq -r '.content')
      echo "✓ $agent: $content"
      ;;
    swarm_stop)
      success=$(echo "$event" | jq -r '.success')
      total_cost=$(echo "$event" | jq -r '.total_cost')
      duration=$(echo "$event" | jq -r '.duration')

      if [ "$success" = "true" ]; then
        echo "✓ Success! Cost: \$$total_cost, Duration: ${duration}s"
      else
        echo "✗ Failed! Duration: ${duration}s"
        exit 1
      fi
      ;;
  esac
done
```

**Collecting results**:
```bash
#!/bin/bash
# collect-results.sh - Collect all events into structured output

output_file="results.json"

# Collect all events into JSON array
swarm run config.yml -p "Task" --output-format json | \
  jq -s '.' > "$output_file"

# Extract summary information
total_cost=$(jq '[.[] | select(.usage) | .usage.cost] | add' "$output_file")
success=$(jq '.[-1].success' "$output_file")
agents=$(jq '.[-1].agents_involved' "$output_file")

echo "Summary:"
echo "  Success: $success"
echo "  Total Cost: \$$total_cost"
echo "  Agents: $agents"
```

### Processing NDJSON in Ruby

```ruby
#!/usr/bin/env ruby
# process-ndjson.rb - Process NDJSON output in Ruby

require 'json'
require 'open3'

cmd = "swarm run config.yml -p 'Task' --output-format json"
total_cost = 0.0

Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
  stdout.each_line do |line|
    event = JSON.parse(line)

    case event['type']
    when 'swarm_start'
      puts "🚀 Starting: #{event['swarm_name']}"
    when 'agent_step'
      cost = event.dig('usage', 'cost') || 0.0
      total_cost += cost
      puts "💭 #{event['agent']} (cost: $#{cost})"
    when 'agent_stop'
      puts "✓ #{event['agent']}: #{event['content']}"
    when 'swarm_stop'
      puts "\n📊 Summary:"
      puts "  Success: #{event['success']}"
      puts "  Duration: #{event['duration']}s"
      puts "  Total Cost: $#{event['total_cost']}"
      puts "  Agents: #{event['agents_involved'].join(', ')}"
    end
  end
end
```

### Useful Flags

**Quiet mode** - Suppress progress output (only show final result):
```bash
swarm run config.yml -p "Task" --quiet
```

**Truncate mode** - Truncate long outputs for concise view:
```bash
swarm run config.yml -p "Summarize all files" --truncate
```

**Verbose mode** - Show additional debug information:
```bash
swarm run config.yml -p "Task" --verbose
```

### Exit Codes

SwarmCLI uses standard exit codes:

| Exit Code | Meaning |
|-----------|---------|
| `0` | Success |
| `1` | Error (configuration, execution, etc.) |
| `130` | User cancelled (Ctrl+C) |

**Use in scripts**:
```bash
if swarm run config.yml -p "Task" --quiet; then
  echo "✓ Success!"
else
  echo "✗ Failed with exit code $?"
  exit 1
fi
```

### Piping and Redirection

**Pipe prompt from file**:
```bash
cat prompt.txt | swarm run config.yml -p
```

**Redirect output to file**:
```bash
swarm run config.yml -p "Generate report" > report.txt 2>&1
```

**Save JSON events to file**:
```bash
swarm run config.yml -p "Task" --output-format json > events.ndjson
```

**Process saved NDJSON file**:
```bash
cat events.ndjson | jq -c 'select(.type == "agent_stop")'
```

**Chain with other commands**:
```bash
# Get list of files, then process each
ls *.rb | xargs -I {} swarm run config.yml -p "Analyze {}" --quiet

# Process multiple prompts from file
cat prompts.txt | while read prompt; do
  swarm run config.yml -p "$prompt" --quiet
done
```

**Combine with jq for JSON processing**:
```bash
# Extract final agent response
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "agent_stop")' | tail -1 | jq -r '.content'

# Track costs in real-time
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.usage) | {agent, cost: .usage.cost}'
```

## Configuration Files

SwarmCLI works with both YAML and Ruby DSL configuration files.

### YAML Configuration

Create a file with `.yml` or `.yaml` extension:

**Example** (`team.yml`):
```yaml
version: 2
swarm:
  name: "Development Team"
  lead: architect

  agents:
    architect:
      description: "Lead architect coordinating the team"
      model: "gpt-4"
      system_prompt: |
        You are the lead architect.
        Break down tasks and delegate to specialists.
      tools:
        - Write
        - Edit
      delegates_to:
        - coder
        - reviewer

    coder:
      description: "Writes clean, maintainable code"
      model: "gpt-4"
      system_prompt: "You are an expert programmer."
      tools:
        - Write
        - Edit

    reviewer:
      description: "Reviews code for quality"
      model: "claude-sonnet-4"
      system_prompt: "You review code for bugs and improvements."
```

**Use it**:
```bash
swarm run team.yml
```

### Ruby DSL Configuration

Create a file with `.rb` extension:

**Example** (`team.rb`):
```ruby
SwarmSDK.build do
  name "Development Team"
  lead :architect

  agent :architect do
    description "Lead architect coordinating the team"
    model "gpt-4"
    system_prompt "You are the lead architect. Break down tasks and delegate to specialists."
    tools :Write, :Edit
    delegates_to :coder, :reviewer
  end

  agent :coder do
    description "Writes clean, maintainable code"
    model "gpt-4"
    system_prompt "You are an expert programmer."
    tools :Write, :Edit
  end

  agent :reviewer do
    description "Reviews code for quality"
    model "claude-sonnet-4"
    system_prompt "You review code for bugs and improvements."
  end
end
```

**Use it**:
```bash
swarm run team.rb
```

### When to Use Which Format

**Use YAML when**:
- You prefer declarative configuration
- Your team is more familiar with YAML
- You want simpler, more readable configs
- You're defining shell-based hooks

**Use Ruby DSL when**:
- You need dynamic configuration (variables, conditionals)
- You want IDE autocomplete and type checking
- You're writing hooks as Ruby blocks
- You need programmatic agent generation

**Both formats work identically with SwarmCLI** - choose what fits your workflow.

## Common Workflows

### Workflow 1: Exploratory Development

Use interactive mode to explore and iterate:

```bash
swarm run dev-team.yml
```

```
You ❯ What files are in src/?
# Agent lists files

You ❯ Read main.rb and explain what it does
# Agent reads and explains

You ❯ Refactor the long function on line 45
# Agent refactors code

You ❯ /exit
```

**Why this works**: Interactive mode preserves context, so each message builds on previous ones. The agent remembers what files you discussed and what changes were made.

### Workflow 2: Automated Code Review in CI/CD

Use non-interactive mode with NDJSON output for automated reviews:

```bash
#!/bin/bash
# ci-review.sh - Automated code review for CI/CD

FILES=$(git diff --name-only main...HEAD | grep '\.rb$')

exit_code=0

for file in $FILES; do
  echo "Reviewing $file..."

  # Run review and extract final response
  content=$(swarm run reviewer.yml -p "Review $file for bugs and style issues" \
    --output-format json | \
    jq -c 'select(.type == "agent_stop")' | tail -1 | jq -r '.content')

  # Check if review succeeded
  if [ $? -eq 0 ]; then
    echo "$content" > "reviews/$file.txt"
    echo "✓ Review complete"

    # Check for critical issues in response
    if echo "$content" | grep -q "CRITICAL\|ERROR\|SECURITY"; then
      echo "✗ Critical issues found in $file"
      exit_code=1
    fi
  else
    echo "✗ Review failed for $file"
    exit_code=1
  fi
done

exit $exit_code
```

**Why this works**: Non-interactive mode with NDJSON output is perfect for CI/CD. Structured output is easy to parse, and exit codes integrate seamlessly with CI systems.

### Workflow 3: Batch Processing with Real-Time Cost Tracking

Process multiple items with streaming cost monitoring:

```bash
#!/bin/bash
# batch-process.sh - Process issues with real-time cost tracking

total_cost=0

while IFS= read -r issue; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Processing: $issue"

  # Process with real-time event monitoring
  swarm run analyzer.yml -p "Analyze: $issue" --output-format json | \
    while IFS= read -r event; do
      type=$(echo "$event" | jq -r '.type')

      case $type in
        agent_step)
          cost=$(echo "$event" | jq -r '.usage.cost // 0')
          if [ "$cost" != "0" ]; then
            echo "  💭 Cost so far: \$$cost"
          fi
          ;;
        tool_call)
          tool=$(echo "$event" | jq -r '.tool')
          echo "  🔧 Using tool: $tool"
          ;;
        swarm_stop)
          cost=$(echo "$event" | jq -r '.total_cost')
          success=$(echo "$event" | jq -r '.success')
          content=$(echo "$event" | jq -r '.content // ""')

          # Save result
          echo "{\"issue\": \"$issue\", \"analysis\": \"$content\", \"cost\": $cost}" >> results.json

          # Update running total
          total_cost=$(echo "$total_cost + $cost" | bc)

          if [ "$success" = "true" ]; then
            echo "  ✓ Complete. Cost: \$$cost. Total so far: \$$total_cost"
          else
            echo "  ✗ Failed. Cost: \$$cost"
          fi
          ;;
      esac
    done
done < issues.txt

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Final Summary"
echo "  Issues processed: $(wc -l < issues.txt)"
echo "  Total cost: \$$total_cost"
```

**Why this works**: NDJSON streaming lets you process events in real-time. You can monitor progress, track costs, and respond to events as they happen - perfect for long-running batch operations.

### Workflow 4: Multi-Stage Pipeline

Combine different modes for a complete workflow:

```bash
#!/bin/bash
# pipeline.sh - Multi-stage development pipeline

set -e  # Exit on any error

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Stage 1: Planning (Interactive)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Interactive planning session
swarm run planner.yml "Plan a REST API for user management"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Stage 2: Implementation (Non-Interactive)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Implement in non-interactive mode
swarm run coder.yml -p "Implement the planned API" --quiet

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Stage 3: Review (Non-Interactive with JSON)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Review with structured output
swarm run reviewer.yml -p "Review the implementation" --output-format json | \
  jq -c 'select(.type == "swarm_stop")' | tail -1 > review-result.json

success=$(jq -r '.success' review-result.json)
cost=$(jq -r '.total_cost' review-result.json)
agents=$(jq -r '.agents_involved | join(", ")' review-result.json)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Pipeline Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Status: $success"
echo "  Review Cost: \$$cost"
echo "  Agents Used: $agents"

if [ "$success" = "true" ]; then
  echo "  ✓ Pipeline complete!"
  exit 0
else
  echo "  ✗ Pipeline failed!"
  exit 1
fi
```

**Why this works**: Different stages benefit from different modes. Planning is interactive for human input, implementation is automated, and review provides structured output for downstream processing.

### Workflow 5: Real-Time Monitoring Dashboard

Monitor swarm execution with live updates:

```bash
#!/bin/bash
# monitor.sh - Real-time monitoring dashboard

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Swarm Execution Monitor"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

running_cost=0
step_count=0
tool_calls=0

swarm run config.yml -p "$1" --output-format json | while IFS= read -r event; do
  type=$(echo "$event" | jq -r '.type')
  timestamp=$(echo "$event" | jq -r '.timestamp' | cut -d'T' -f2 | cut -d'.' -f1)

  case $type in
    swarm_start)
      swarm_name=$(echo "$event" | jq -r '.swarm_name')
      lead=$(echo "$event" | jq -r '.lead_agent')
      echo -e "${BLUE}[$timestamp]${NC} 🚀 Started: $swarm_name (lead: $lead)"
      ;;
    agent_step)
      agent=$(echo "$event" | jq -r '.agent')
      cost=$(echo "$event" | jq -r '.usage.cost // 0')
      tokens=$(echo "$event" | jq -r '.usage.total_tokens // 0')

      if [ "$cost" != "0" ]; then
        running_cost=$(echo "$running_cost + $cost" | bc)
        step_count=$((step_count + 1))
        echo -e "${YELLOW}[$timestamp]${NC} 💭 $agent • step $step_count • $tokens tokens • +\$$cost (total: \$$running_cost)"
      fi
      ;;
    tool_call)
      tool=$(echo "$event" | jq -r '.tool')
      tool_calls=$((tool_calls + 1))
      echo -e "${BLUE}[$timestamp]${NC} 🔧 Tool: $tool"
      ;;
    agent_delegation)
      agent=$(echo "$event" | jq -r '.agent')
      to=$(echo "$event" | jq -r '.delegate_to')
      echo -e "${BLUE}[$timestamp]${NC} 👉 Delegation: $agent → $to"
      ;;
    agent_stop)
      agent=$(echo "$event" | jq -r '.agent')
      reason=$(echo "$event" | jq -r '.finish_reason')
      echo -e "${GREEN}[$timestamp]${NC} ✓ $agent complete ($reason)"
      ;;
    swarm_stop)
      success=$(echo "$event" | jq -r '.success')
      duration=$(echo "$event" | jq -r '.duration')
      total_cost=$(echo "$event" | jq -r '.total_cost')
      agents=$(echo "$event" | jq -r '.agents_involved | join(", ")')

      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📊 Execution Complete"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

      if [ "$success" = "true" ]; then
        echo -e "  Status: ${GREEN}✓ Success${NC}"
      else
        echo -e "  Status: ${RED}✗ Failed${NC}"
      fi

      echo "  Duration: ${duration}s"
      echo "  Total Cost: \$$total_cost"
      echo "  Steps: $step_count"
      echo "  Tool Calls: $tool_calls"
      echo "  Agents: $agents"
      ;;
  esac
done
```

**Use it**:
```bash
./monitor.sh "Build a user authentication system"
```

**Why this works**: NDJSON streaming enables real-time monitoring. You see each event as it happens, providing insight into agent behavior, costs, and progress.

## Common Pitfalls and Solutions

### Pitfall 1: Wrong Gem Name

**Error**:
```bash
# ❌ Wrong gem name
gem install swarm-sdk      # Wrong!
gem install swarmcore      # Wrong!
gem install swarm-cli      # Wrong (hyphen instead of underscore)!
```

**Solution**:
```bash
# ✅ Correct gem name (underscore, not hyphen)
gem install swarm_cli

# This automatically installs:
# - swarm_cli (the CLI)
# - swarm_sdk (the library)
```

### Pitfall 2: Wrong Executable Name

**Error**:
```bash
# ❌ Wrong executable name
swarm_cli run config.yml   # Wrong!
swarmcli run config.yml    # Wrong!
```

**Solution**:
```bash
# ✅ Correct executable name
swarm run config.yml
```

### Pitfall 3: Wrong Ruby Version

**Error**:
```bash
# Using Ruby 3.1 or earlier
ruby -v
# => ruby 3.1.0

gem install swarm_cli
# => ERROR: swarm_cli requires Ruby >= 3.2.0
```

**Solution**:
```bash
# ✅ Use Ruby 3.2.0 or higher
rbenv install 3.2.0
rbenv global 3.2.0

# Or with rvm
rvm install 3.2.0
rvm use 3.2.0

# Verify
ruby -v
# => ruby 3.2.0 (or higher)

# Now install
gem install swarm_cli
```

### Pitfall 4: Mixing Interactive and Non-Interactive Flags

**Error**:
```bash
# ❌ Can't use -p flag without a prompt
swarm run config.yml -p
```

**Output**:
```
Error: Non-interactive mode (-p) requires a prompt (provide as argument or via stdin)
```

**Solution**:
```bash
# ✅ Provide prompt as argument
swarm run config.yml -p "Your task"

# ✅ Or provide via stdin
echo "Your task" | swarm run config.yml -p
```

### Pitfall 5: Using JSON Format in Interactive Mode

**Error**:
```bash
# ❌ JSON format doesn't work with REPL
swarm run config.yml --output-format json
```

**Output**:
```
Error: Interactive mode is not compatible with --output-format json
```

**Solution**:
```bash
# ✅ Use JSON only in non-interactive mode
swarm run config.yml -p "Task" --output-format json

# ✅ Or use default human format in interactive mode
swarm run config.yml
```

### Pitfall 6: Expecting Single JSON Object Instead of NDJSON

**CRITICAL PITFALL**: This is the most common mistake when working with JSON output.

**Error**:
```bash
# ❌ Trying to parse as single JSON object
result=$(swarm run config.yml -p "Task" --output-format json)
echo "$result" | jq '.content'

# Output:
# parse error: Expected value at line 2, column 1
```

**Why it fails**: `jq` expects a single JSON object by default, but SwarmCLI outputs NDJSON (one JSON object per line).

**What you're getting** (NDJSON):
```
{"type":"swarm_start","swarm_name":"Test",...}
{"type":"agent_step","agent":"helper",...}
{"type":"agent_stop","agent":"helper",...}
{"type":"swarm_stop","success":true,...}
```

**What you're expecting** (single JSON):
```json
{
  "swarm_name": "Test",
  "content": "...",
  "success": true
}
```

**Solutions**:

**✅ Solution 1: Parse NDJSON line by line**
```bash
# Extract final agent response
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "agent_stop")' | tail -1 | jq -r '.content'
```

**✅ Solution 2: Collect all events into array**
```bash
# Use jq -s to slurp all lines into array
result=$(swarm run config.yml -p "Task" --output-format json | jq -s '.')
echo "$result" | jq '.[-1].content'
```

**✅ Solution 3: Filter specific event type**
```bash
# Get success status from final event
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "swarm_stop")' | tail -1 | jq -r '.success'
```

**✅ Solution 4: Process line by line in bash**
```bash
swarm run config.yml -p "Task" --output-format json | while IFS= read -r event; do
  type=$(echo "$event" | jq -r '.type')
  if [ "$type" = "swarm_stop" ]; then
    success=$(echo "$event" | jq -r '.success')
    echo "Success: $success"
  fi
done
```

**✅ Solution 5: Save to file and process**
```bash
# Save NDJSON to file
swarm run config.yml -p "Task" --output-format json > events.ndjson

# Process saved file
cat events.ndjson | jq -c 'select(.type == "agent_stop")'

# Or collect into array
jq -s '.' events.ndjson > events-array.json
```

### Pitfall 7: Configuration File Not Found

**Error**:
```bash
# ❌ File doesn't exist
swarm run nonexistent.yml
```

**Output**:
```
Error: Configuration file not found: nonexistent.yml
```

**Solution**:
```bash
# ✅ Check the file exists
ls config.yml

# ✅ Use absolute or correct relative path
swarm run ./config.yml
swarm run /full/path/to/config.yml

# ✅ Check your current directory
pwd
ls *.yml
```

### Pitfall 8: Missing API Key

**Error**:
```bash
swarm run config.yml -p "Task"
```

**Output**:
```
Fatal error: No API key found for provider 'openai'
```

**Solution**:
```bash
# ✅ Set API key as environment variable
export OPENAI_API_KEY="sk-your-key-here"
swarm run config.yml -p "Task"

# ✅ Or use .env file
echo "OPENAI_API_KEY=sk-your-key-here" > .env
swarm run config.yml -p "Task"

# ✅ Verify API key is set
echo $OPENAI_API_KEY
```

### Pitfall 9: Forgetting to Exit Interactive Mode

**Issue**: Leaving the REPL running in the background consumes resources and may incur costs.

**Solution**:
```
# Always exit properly
You ❯ /exit

# Or press Ctrl+D

# Or press Ctrl+C (will show cancellation message)
```

**Tip**: The session summary shows you exactly what was consumed, helping you track usage.

### Pitfall 10: Using Wrong jq Flags for NDJSON

**Error**:
```bash
# ❌ Using jq without -c flag loses event boundaries
swarm run config.yml -p "Task" --output-format json | jq .

# Output: Pretty-printed JSON that's no longer valid NDJSON
```

**Solution**:
```bash
# ✅ Use -c (compact) flag to preserve NDJSON format
swarm run config.yml -p "Task" --output-format json | jq -c .

# ✅ Use -c when filtering
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "agent_stop")'
```

## Next Steps

Congratulations! You've learned how to use SwarmCLI effectively.

### Dive Deeper

**Core Documentation**:
- **[Getting Started with SwarmSDK](getting-started.md)** - Learn to write swarm configurations
- **[Complete Tutorial](complete-tutorial.md)** - Master all SwarmSDK features
- **[Rails Integration](rails-integration.md)** - Use SwarmSDK in Rails applications

**Advanced Topics**:
- **[Hooks Complete Guide](hooks-complete-guide.md)** - Master hooks system
- **[Node Workflows](node-workflows-guide.md)** - Build multi-stage pipelines
- **[Performance Tuning](performance-tuning.md)** - Optimize speed and costs

### Key Concepts to Explore

**Interactive vs Non-Interactive**: Understand when to use each mode for maximum productivity.

**NDJSON Event Stream**: Master real-time event processing for monitoring and automation.

**Configuration Management**: Learn to organize and reuse swarm configurations across projects.

**Performance Optimization**: Discover techniques for faster execution and lower costs.

## Where to Get Help

- **Documentation**: [SwarmSDK Guides](../README.md)
- **Examples**: [Example Configurations](../../../examples/v2/)
- **Issues**: [GitHub Issues](https://github.com/parruda/claude-swarm/issues)

## Summary

You've learned:

✅ **What SwarmCLI is** - A separate gem (`swarm_cli`) that provides CLI for SwarmSDK

✅ **Installation** - `gem install swarm_cli` (automatically installs `swarm_sdk`)

✅ **Executable name** - Use `swarm` command (not `swarm_cli`)

✅ **Ruby requirement** - Ruby 3.2.0 or higher required

✅ **Execution modes** - Interactive (REPL) for conversations, non-interactive for automation

✅ **Commands** - `run`, `migrate`, `mcp serve`, and `mcp tools`

✅ **Interactive features** - REPL commands, tab completion, context preservation, session summaries

✅ **Non-interactive features** - NDJSON event streaming, real-time monitoring, scripting support

✅ **NDJSON format** - Newline-delimited JSON (one event per line), not single JSON object

✅ **Processing NDJSON** - Use `jq -c`, `jq -s`, or line-by-line bash processing

✅ **Configuration files** - Both YAML and Ruby DSL support

✅ **Common workflows** - Exploratory development, automated reviews, batch processing, pipelines, monitoring

**Next**: [Getting Started with SwarmSDK →](getting-started.md)

---

## Quick Reference Card

```bash
# ════════════════════════════════════════════════════════════
# INSTALLATION
# ════════════════════════════════════════════════════════════

gem install swarm_cli                 # Installs swarm_cli + swarm_sdk
                                      # Executable: swarm (not swarm_cli)
                                      # Requires: Ruby >= 3.2.0

# ════════════════════════════════════════════════════════════
# INTERACTIVE MODE (REPL)
# ════════════════════════════════════════════════════════════

swarm run config.yml                           # Start REPL
swarm run config.yml "Initial message"         # REPL with initial message
echo "Message" | swarm run config.yml          # REPL with piped input

# REPL Commands (type in REPL):
# /help      - Show help
# /history   - Show conversation history
# /clear     - Clear screen
# /exit      - Exit (or Ctrl+D)

# ════════════════════════════════════════════════════════════
# NON-INTERACTIVE MODE
# ════════════════════════════════════════════════════════════

swarm run config.yml -p "Task"                 # One-shot execution
echo "Task" | swarm run config.yml -p          # From stdin
swarm run config.yml -p "Task" --quiet         # Quiet mode (no progress)

# ════════════════════════════════════════════════════════════
# JSON OUTPUT (NDJSON FORMAT)
# ════════════════════════════════════════════════════════════

# CRITICAL: Output is NDJSON (newline-delimited JSON)
# - Each line is a complete JSON event
# - NOT a single JSON object
# - Process line by line, not as whole

swarm run config.yml -p "Task" --output-format json

# Parse NDJSON (extract final agent response):
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "agent_stop")' | tail -1 | jq -r '.content'

# Track costs in real-time:
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.usage) | {agent, cost: .usage.cost}'

# Get success status:
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "swarm_stop")' | tail -1 | jq -r '.success'

# Collect all events into array:
swarm run config.yml -p "Task" --output-format json | jq -s '.'

# Process line by line in bash:
swarm run config.yml -p "Task" --output-format json | while IFS= read -r event; do
  type=$(echo "$event" | jq -r '.type')
  # Process $event...
done

# ════════════════════════════════════════════════════════════
# OTHER COMMANDS
# ════════════════════════════════════════════════════════════

swarm migrate old.yml --output new.yml         # Migrate v1 to v2
swarm mcp serve config.yml                     # Start MCP server
swarm mcp tools                                # Expose all tools
swarm mcp tools Read Write Edit                # Expose specific tools

# ════════════════════════════════════════════════════════════
# USEFUL FLAGS
# ════════════════════════════════════════════════════════════

--output-format json       # NDJSON event stream (non-interactive only)
--quiet                    # Suppress progress output
--truncate                 # Truncate long outputs
--verbose                  # Show debug information

# ════════════════════════════════════════════════════════════
# CONFIGURATION FILES
# ════════════════════════════════════════════════════════════

# YAML format:
#   config.yml or config.yaml

# Ruby DSL format:
#   config.rb

# Both formats work identically with SwarmCLI

# ════════════════════════════════════════════════════════════
# EXIT CODES
# ════════════════════════════════════════════════════════════

# 0   - Success
# 1   - Error (configuration, execution, etc.)
# 130 - User cancelled (Ctrl+C)

# ════════════════════════════════════════════════════════════
# NDJSON EVENT TYPES
# ════════════════════════════════════════════════════════════

# swarm_start          - Swarm execution begins
# user_prompt          - User message sent to agent
# agent_step           - Agent produces intermediate output
# agent_stop           - Agent completes response
# tool_call            - Agent invokes a tool
# tool_result          - Tool returns result
# agent_delegation     - Agent delegates to another agent
# delegation_result    - Delegated agent completes
# delegation_error     - Delegation fails
# node_start           - Node execution begins (workflows)
# node_stop            - Node execution completes (workflows)
# model_lookup_warning - Unknown model in config
# context_limit_warning - Context usage threshold crossed
# swarm_stop           - Swarm execution completes

# ════════════════════════════════════════════════════════════
# COMMON PATTERNS
# ════════════════════════════════════════════════════════════

# Extract final content:
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "agent_stop")' | tail -1 | jq -r '.content'

# Calculate total cost:
swarm run config.yml -p "Task" --output-format json | \
  jq -s '[.[] | select(.usage) | .usage.cost] | add'

# Filter tool calls:
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "tool_call") | {tool, arguments}'

# Get all agents involved:
swarm run config.yml -p "Task" --output-format json | \
  jq -c 'select(.type == "swarm_stop")' | tail -1 | jq -r '.agents_involved'

# Save to file and process later:
swarm run config.yml -p "Task" --output-format json > events.ndjson
cat events.ndjson | jq -c 'select(.type == "agent_stop")'
```

**Remember**: JSON output is **NDJSON** (newline-delimited JSON), not a single JSON object!
