# Ruby DSL Reference

Complete Ruby DSL API reference for building swarms programmatically.

---

## Overview

The Ruby DSL provides a fluent, type-safe API for building swarms with IDE support and Ruby's full language features. All configuration can be done programmatically with variables, conditionals, loops, and functions.

**Key benefits:**
- Full Ruby language features (variables, conditionals, loops, functions)
- Ruby blocks for hooks (inline logic, no external scripts)
- Type-safe, chainable API
- IDE autocompletion and inline documentation

**Basic structure:**
```ruby
swarm = SwarmSDK.build do
  name "Swarm Name"
  lead :agent_name

  agent :agent_name do
    # Agent configuration
  end
end

result = swarm.execute("Task prompt")
```

---

## Top-Level Methods

### SwarmSDK.configure

Configure global SwarmSDK settings.

**Signature:**
```ruby
SwarmSDK.configure {|config| ... } → void
```

**Parameters:**
- `block` (required): Configuration block

**Available settings:**
- `webfetch_provider` (String): LLM provider for WebFetch tool (e.g., "anthropic", "openai", "ollama")
- `webfetch_model` (String): Model name for WebFetch tool (e.g., "claude-3-5-haiku-20241022")
- `webfetch_base_url` (String, optional): Custom base URL for the provider
- `webfetch_max_tokens` (Integer): Maximum tokens for WebFetch LLM responses (default: 4096)

**Description:**
Global configuration that applies to all swarms. Currently used to configure the WebFetch tool's LLM processing behavior.

When `webfetch_provider` and `webfetch_model` are set, the WebFetch tool will process fetched web content using the configured LLM. Without this configuration, WebFetch returns raw markdown.

**Example:**
```ruby
# Configure WebFetch to use Anthropic's Claude Haiku
SwarmSDK.configure do |config|
  config.webfetch_provider = "anthropic"
  config.webfetch_model = "claude-3-5-haiku-20241022"
  config.webfetch_max_tokens = 4096
end

# Configure WebFetch to use local Ollama
SwarmSDK.configure do |config|
  config.webfetch_provider = "ollama"
  config.webfetch_model = "llama3.2"
  config.webfetch_base_url = "http://localhost:11434"
end

# Reset to defaults (disables WebFetch LLM processing)
SwarmSDK.reset_settings!
```

---

### SwarmSDK.build

Build a swarm using the DSL.

**Signature:**
```ruby
SwarmSDK.build(&block) → Swarm | NodeOrchestrator
```

**Parameters:**
- `block` (required): Configuration block

**Returns:**
- `Swarm`: For single-swarm configurations
- `NodeOrchestrator`: For multi-node workflow configurations

**Example:**
```ruby
swarm = SwarmSDK.build do
  name "Development Team"
  lead :backend

  agent :backend do
    model "gpt-5"
    tools :Read, :Write, :Bash
  end
end
```

---

### SwarmSDK.refresh_models_silently

Refresh the LLM model registry silently (called automatically by CLI).

**Signature:**
```ruby
SwarmSDK.refresh_models_silently → void
```

**Description:**
Updates RubyLLM's model registry to ensure latest model information is available. Called automatically by SwarmCLI before execution.

---

## Swarm Builder DSL

Methods available in the `SwarmSDK.build` block.

### name

Set the swarm name.

**Signature:**
```ruby
name(swarm_name) → void
```

**Parameters:**
- `swarm_name` (String, required): Human-readable swarm name

**Example:**
```ruby
name "Development Team"
name "Code Review Swarm"
```

---

### lead

Set the lead agent (entry point for execution).

**Signature:**
```ruby
lead(agent_name) → void
```

**Parameters:**
- `agent_name` (Symbol, required): Name of lead agent

**Example:**
```ruby
lead :backend
lead :coordinator
```

---

### use_scratchpad

Enable or disable shared scratchpad tools for all agents.

**Signature:**
```ruby
use_scratchpad(enabled) → void
```

**Parameters:**
- `enabled` (Boolean, required): Whether to enable scratchpad tools

**Default:** `true` (scratchpad tools enabled)

**Description:**
Controls whether agents have access to scratchpad tools (ScratchpadWrite, ScratchpadRead, ScratchpadList). Scratchpad is volatile (in-memory only) and shared across all agents in the swarm.

**Example:**
```ruby
# Enable scratchpad (default)
use_scratchpad true

# Disable scratchpad
use_scratchpad false
```

---

### agent

Define an agent with its configuration.

**Signature:**
```ruby
agent(name, &block) → void
```

**Parameters:**
- `name` (Symbol, required): Agent name
- `block` (required): Agent configuration block

**Example:**
```ruby
agent :backend do
  model "gpt-5"
  description "Backend API developer"
  tools :Read, :Write, :Bash
  delegates_to :database

  hook :pre_tool_use, matcher: "Bash" do |ctx|
    ctx.halt("Dangerous command") if ctx.tool_call.parameters[:command].include?("rm -rf")
  end
end
```

---

### all_agents

Configure settings that apply to all agents.

**Signature:**
```ruby
all_agents(&block) → void
```

**Parameters:**
- `block` (required): Configuration block (uses [AllAgentsBuilder DSL](#all-agents-builder-dsl))

**Description:**
Settings configured here apply to ALL agents but can be overridden at the agent level. Useful for shared configuration like provider, timeout, or global permissions.

**Example:**
```ruby
all_agents do
  provider :openai
  base_url "http://proxy.example.com/v1"
  timeout 180
  tools :Read, :Write
  coding_agent false

  permissions do
    tool(:Write).deny_paths "secrets/**"
  end

  hook :pre_tool_use, matcher: "Write" do |ctx|
    # Validation for all agents
  end
end
```

---

### hook

Add a swarm-level hook (swarm_start or swarm_stop only).

**Signature:**
```ruby
hook(event, command: nil, timeout: nil, &block) → void
```

**Parameters:**
- `event` (Symbol, required): Event type (`:swarm_start` or `:swarm_stop`)
- `command` (String, optional): Shell command to execute
- `timeout` (Integer, optional): Command timeout in seconds (default: 60)
- `block` (optional): Ruby block for inline logic

**Valid events:** `:swarm_start`, `:swarm_stop`

**Example with block:**
```ruby
hook :swarm_start do |ctx|
  puts "Swarm starting: #{ctx.metadata[:prompt]}"
end

hook :swarm_stop do |ctx|
  puts "Duration: #{ctx.metadata[:duration]}s"
  puts "Cost: $#{ctx.metadata[:total_cost]}"
end
```

**Example with command:**
```ruby
hook :swarm_start, command: "echo 'Starting' >> log.txt"
hook :swarm_stop, command: "scripts/cleanup.sh", timeout: 30
```

---

### node

Define a node (stage in multi-step workflow).

**Signature:**
```ruby
node(name, &block) → void
```

**Parameters:**
- `name` (Symbol, required): Node name
- `block` (required): Node configuration block (uses [NodeBuilder DSL](#node-builder-dsl))

**Description:**
Nodes enable multi-stage workflows where different agent teams collaborate in sequence. Each node is an independent swarm execution.

**Example:**
```ruby
node :planning do
  agent(:architect)

  input do |ctx|
    "Plan this task: #{ctx.original_prompt}"
  end

  output do |ctx|
    File.write("plan.txt", ctx.content)
    "Key decisions: #{extract_decisions(ctx.content)}"
  end
end

node :implementation do
  agent(:backend).delegates_to(:tester)
  agent(:tester)

  depends_on :planning

  input do |ctx|
    plan = ctx.all_results[:planning].content
    "Implement based on:\n#{plan}"
  end
end
```

---

### start_node

Set the starting node for workflow execution.

**Signature:**
```ruby
start_node(name) → void
```

**Parameters:**
- `name` (Symbol, required): Name of starting node

**Required when:** Nodes are defined

**Example:**
```ruby
start_node :planning

node :planning do
  # ...
end

node :implementation do
  depends_on :planning
end
```

---

## Agent Builder DSL

Methods available in the `agent` block.

### model

Set the LLM model.

**Signature:**
```ruby
model(model_name) → void
model() → String  # getter
```

**Parameters:**
- `model_name` (String, required): Model identifier

**Default:** `"gpt-5"`

**Common models:**
- OpenAI: `"gpt-5"`, `"gpt-4o"`, `"o4"`, `"o4-mini"`
- Anthropic: `"claude-sonnet-4"`, `"claude-opus-4"`
- Google: `"gemini-2.5-flash"`, `"gemini-2.0-pro"`
- DeepSeek: `"deepseek-chat"`, `"deepseek-reasoner"`

**Example:**
```ruby
model "gpt-5"
model "claude-sonnet-4"
model "deepseek-reasoner"
```

---

### provider

Set the LLM provider.

**Signature:**
```ruby
provider(provider_name) → void
provider() → String  # getter
```

**Parameters:**
- `provider_name` (String | Symbol, required): Provider name

**Default:** `"openai"`

**Supported providers:**
- `openai`: OpenAI
- `anthropic`: Anthropic Claude
- `google`: Google AI
- `deepseek`: DeepSeek
- `openrouter`: OpenRouter
- `mistral`: Mistral AI
- `perplexity`: Perplexity

**Example:**
```ruby
provider :openai
provider "anthropic"
provider :deepseek
```

---

### base_url

Set custom API endpoint (for proxies or compatible APIs).

**Signature:**
```ruby
base_url(url) → void
base_url() → String  # getter
```

**Parameters:**
- `url` (String, required): API endpoint URL

**Default:** Provider's default endpoint

**Auto-sets:** `assume_model_exists: true` (skips model validation)

**Example:**
```ruby
base_url "http://localhost:8080/v1"
base_url "https://proxy.example.com/v1"
base_url "https://openrouter.ai/api/v1"
```

---

### api_version

Set API version for OpenAI-compatible providers.

**Signature:**
```ruby
api_version(version) → void
api_version() → String  # getter
```

**Parameters:**
- `version` (String, required): API version path

**Valid values:**
- `"v1/chat/completions"`: Standard chat completions (default)
- `"v1/responses"`: Extended responses format

**Compatible providers:** `openai`, `deepseek`, `perplexity`, `mistral`, `openrouter`

**Example:**
```ruby
# Standard chat completions
api_version "v1/chat/completions"

# Extended responses
api_version "v1/responses"
```

---

### description

Set agent description (required).

**Signature:**
```ruby
description(text) → void
```

**Parameters:**
- `text` (String, required): Human-readable description

**Description:**
Describes the agent's role and responsibilities. Required for all agents.

**Example:**
```ruby
description "Backend API developer specializing in Ruby on Rails"
description "Frontend developer with React and TypeScript expertise"
```

---

### directory

Set agent's working directory.

**Signature:**
```ruby
directory(dir) → void
```

**Parameters:**
- `dir` (String, required): Directory path (absolute or relative)

**Default:** `"."`

**Description:**
All file operations (Read, Write, Edit) are relative to this directory. The directory must exist.

**Example:**
```ruby
directory "."
directory "backend"
directory "/absolute/path/to/workspace"
```

---

### system_prompt

Set custom system prompt text.

**Signature:**
```ruby
system_prompt(text) → void
```

**Parameters:**
- `text` (String, required): Custom prompt text

**Default:** `nil`

**Combination with `coding_agent`:**
- `coding_agent: false` (default): Uses only custom prompt + TODO/Scratchpad info
- `coding_agent: true`: Prepends base coding prompt, then custom prompt

**Example:**
```ruby
system_prompt "You are a backend API developer. Focus on clean, testable code."
system_prompt <<~PROMPT
  You are a code reviewer. For each file:
  1. Check for bugs and edge cases
  2. Suggest improvements
  3. Verify test coverage
PROMPT
```

---

### coding_agent

Enable/disable base coding prompt.

**Signature:**
```ruby
coding_agent(enabled) → void
```

**Parameters:**
- `enabled` (Boolean, required): Include base prompt

**Default:** `false`

**Behavior:**
- `false`: Uses only custom `system_prompt` + TODO/Scratchpad sections
- `true`: Prepends comprehensive base coding prompt, then custom prompt

**Example:**
```ruby
coding_agent true   # Include base prompt for coding tasks
coding_agent false  # Custom prompt only (default)
```

---

### tools

Add tools to the agent.

**Signature:**
```ruby
tools(*tool_names, include_default: true) → void
```

**Parameters:**
- `tool_names` (Symbol, variadic): Tool names to add
- `include_default` (Boolean, keyword): Include default tools

**Default tools (when `include_default: true`):**
- `Read`, `Glob`, `Grep`, `TodoWrite`, `Think`, `WebFetch`

**Scratchpad tools** (added if `scratchpad true` at swarm level, default):
- `ScratchpadWrite`, `ScratchpadRead`, `ScratchpadList`

**Memory tools** (added if agent has `memory` configured):
- `MemoryWrite`, `MemoryRead`, `MemoryEdit`, `MemoryMultiEdit`, `MemoryGlob`, `MemoryGrep`, `MemoryDelete`

**Additional tools:**
- `Write`, `Edit`, `MultiEdit`, `Bash`

**Behavior:**
- Multiple calls are cumulative (tools are merged)
- Duplicates are automatically removed (uses Set internally)

**Example:**
```ruby
# With defaults
tools :Write, :Bash

# Without defaults (explicit tools only)
tools :Read, :Write, :Bash, include_default: false

# Multiple calls (cumulative)
tools :Read, :Write
tools :Edit, :Bash  # Now has: Read, Write, Edit, Bash + defaults
```

---

### delegates_to

Set delegation targets (agents this agent can delegate to).

**Signature:**
```ruby
delegates_to(*agent_names) → void
```

**Parameters:**
- `agent_names` (Symbol, variadic): Names of agents to delegate to

**Default:** `[]`

**Behavior:**
- Multiple calls are cumulative
- Creates a `DelegateTaskTo{Agent}` tool for each target (e.g., `DelegateTaskToDatabase`)

**Example:**
```ruby
delegates_to :database
delegates_to :tester, :reviewer
delegates_to :frontend  # Cumulative - adds to existing list
```

---

### memory

Configure persistent memory storage for this agent.

**Signature:**
```ruby
memory(&block) → void
```

**Parameters:**
- `block` (required): Memory configuration block

**Block DSL:**
- `adapter(symbol)` - Storage adapter (default: `:filesystem`)
- `directory(string)` - Directory where memory.json will be stored (required)

**Description:**
Enables persistent memory for the agent. When configured, the agent automatically gets all 7 memory tools (MemoryWrite, MemoryRead, MemoryEdit, MemoryMultiEdit, MemoryGlob, MemoryGrep, MemoryDelete) and a memory system prompt is appended to help the agent use memory effectively.

Memory is per-agent (isolated) and persistent (survives across sessions).

**Example:**
```ruby
memory do
  adapter :filesystem  # optional, default
  directory ".swarm/agent-memory"
end

# Minimal (adapter defaults to :filesystem)
memory do
  directory ".swarm/my-agent"
end
```

**Future adapters:** `:sqlite`, `:faiss` (not yet implemented)

---

### mcp_server

Add an MCP server configuration.

**Signature:**
```ruby
mcp_server(name, **options) → void
```

**Parameters:**
- `name` (Symbol, required): MCP server name
- `options` (Hash, required): Server configuration

**Transport types:**

**stdio transport:**
```ruby
mcp_server :filesystem,
  type: :stdio,
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed"],
  env: { "VAR" => "value" }  # optional
```

**sse transport:**
```ruby
mcp_server :web,
  type: :sse,
  url: "https://example.com/mcp",
  headers: { authorization: "Bearer token" },
  timeout: 60  # optional
```

**http transport:**
```ruby
mcp_server :api,
  type: :http,
  url: "https://api.example.com/mcp",
  headers: { "api-key" => "key" },
  timeout: 120  # optional
```

---

### permissions

Configure tool permissions.

**Signature:**
```ruby
permissions(&block) → void
```

**Parameters:**
- `block` (required): Permissions configuration block (uses [PermissionsBuilder DSL](#permissions-builder-dsl))

**Description:**
Defines path patterns and command patterns for tool access control. Uses glob patterns for paths and regex for commands.

**Example:**
```ruby
permissions do
  tool(:Write).allow_paths "backend/**/*"
  tool(:Write).deny_paths "backend/secrets/**"
  tool(:Read).deny_paths "config/credentials.yml"
  tool(:Bash).allow_commands "^git (status|diff|log)$"
  tool(:Bash).deny_commands "^rm -rf"
end
```

---

### hook

Add a hook (Ruby block or shell command).

**Signature:**
```ruby
hook(event, matcher: nil, command: nil, timeout: nil, &block) → void
```

**Parameters:**
- `event` (Symbol, required): Event type
- `matcher` (String | Regexp, optional): Tool name pattern (for tool events)
- `command` (String, optional): Shell command to execute
- `timeout` (Integer, optional): Command timeout in seconds (default: 60)
- `block` (optional): Ruby block for inline logic

**Valid events:**
- `:pre_tool_use`: Before tool execution
- `:post_tool_use`: After tool execution
- `:user_prompt`: Before sending user message
- `:agent_stop`: When agent finishes
- `:first_message`: First user message (once per swarm)
- `:pre_delegation`: Before delegating to another agent
- `:post_delegation`: After delegation completes
- `:context_warning`: When context window threshold exceeded

**Example with block:**
```ruby
hook :pre_tool_use, matcher: "Bash" do |ctx|
  if ctx.tool_call.parameters[:command].include?("rm -rf")
    ctx.halt("Dangerous command blocked")
  end
end

hook :post_tool_use, matcher: "Write|Edit" do |ctx|
  puts "Modified: #{ctx.tool_call.parameters[:file_path]}"
end
```

**Example with command:**
```ruby
hook :pre_tool_use, matcher: "Write|Edit", command: "scripts/validate.sh"
hook :post_tool_use, matcher: "Bash", command: "logger 'Command executed'", timeout: 10
```

---

### parameters

Set LLM parameters (temperature, top_p, etc.).

**Signature:**
```ruby
parameters(params) → void
parameters() → Hash  # getter
```

**Parameters:**
- `params` (Hash, required): LLM parameters

**Common parameters:**
- `temperature` (Float): Randomness (0.0-2.0)
- `top_p` (Float): Nucleus sampling (0.0-1.0)
- `max_tokens` (Integer): Maximum output tokens
- `presence_penalty` (Float): Presence penalty (-2.0-2.0)
- `frequency_penalty` (Float): Frequency penalty (-2.0-2.0)

**Example:**
```ruby
parameters temperature: 0.7, top_p: 0.95
parameters max_tokens: 2000, presence_penalty: 0.1
```

---

### headers

Set custom HTTP headers for API requests.

**Signature:**
```ruby
headers(header_hash) → void
headers() → Hash  # getter
```

**Parameters:**
- `header_hash` (Hash, required): HTTP headers

**Example:**
```ruby
headers "X-API-Key" => "key123", "X-Organization" => "org123"
headers authorization: "Bearer token"
```

---

### timeout

Set request timeout.

**Signature:**
```ruby
timeout(seconds) → void
timeout() → Integer  # getter
```

**Parameters:**
- `seconds` (Integer, required): Timeout in seconds

**Default:** `300` (5 minutes)

**Example:**
```ruby
timeout 180  # 3 minutes
timeout 600  # 10 minutes for reasoning models
```

---

### context_window

Set explicit context window size.

**Signature:**
```ruby
context_window(tokens) → void
context_window() → Integer  # getter
```

**Parameters:**
- `tokens` (Integer, required): Context window size in tokens

**Default:** Auto-detected from model registry

**Use case:** Override when using custom models or proxies

**Example:**
```ruby
context_window 128000  # Override for custom model
context_window 200000  # Large context window
```

---

### bypass_permissions

Disable permission checks for this agent.

**Signature:**
```ruby
bypass_permissions(enabled) → void
```

**Parameters:**
- `enabled` (Boolean, required): Bypass permissions

**Default:** `false`

**Warning:** Use with caution - allows unrestricted file/command access

**Example:**
```ruby
bypass_permissions true  # Disable all permission checks
```

---

### max_concurrent_tools

Set maximum concurrent tool calls.

**Signature:**
```ruby
max_concurrent_tools(count) → void
```

**Parameters:**
- `count` (Integer, required): Max concurrent tools

**Default:** Swarm's `default_local_concurrency` (10)

**Example:**
```ruby
max_concurrent_tools 5   # Limit concurrent tools
max_concurrent_tools 20  # Allow more parallelism
```

---

### disable_default_tools

Include default tools (Read, Grep, Glob, TodoWrite, Think, and scratchpad tools).

**Signature:**
```ruby
disable_default_tools(value) → void
```

**Parameters:**
- `enabled` (Boolean, required): Include defaults

**Default:** `true`

**Note:** Prefer `tools(..., include_default: false)` for explicit control

**Example:**
```ruby
disable_default_tools true  # No default tools
```

---

### assume_model_exists

Skip model validation (for custom models).

**Signature:**
```ruby
assume_model_exists(enabled) → void
```

**Parameters:**
- `enabled` (Boolean, required): Skip validation

**Default:** `false` (validate), `true` when `base_url` is set

**Example:**
```ruby
assume_model_exists true  # Skip validation for custom model
```

---

## All-Agents Builder DSL

Methods available in the `all_agents` block.

### model

Set default model for all agents.

**Signature:**
```ruby
model(model_name) → void
```

**Parameters:**
- `model_name` (String, required): Model identifier

**Example:**
```ruby
all_agents do
  model "gpt-5"
end
```

---

### provider

Set default provider for all agents.

**Signature:**
```ruby
provider(provider_name) → void
```

**Parameters:**
- `provider_name` (String | Symbol, required): Provider name

**Example:**
```ruby
all_agents do
  provider :anthropic
end
```

---

### base_url

Set default base URL for all agents.

**Signature:**
```ruby
base_url(url) → void
```

**Parameters:**
- `url` (String, required): API endpoint URL

**Example:**
```ruby
all_agents do
  base_url "https://proxy.example.com/v1"
end
```

---

### api_version

Set default API version for all agents.

**Signature:**
```ruby
api_version(version) → void
```

**Parameters:**
- `version` (String, required): API version path

**Example:**
```ruby
all_agents do
  api_version "v1/responses"
end
```

---

### timeout

Set default timeout for all agents.

**Signature:**
```ruby
timeout(seconds) → void
```

**Parameters:**
- `seconds` (Integer, required): Timeout in seconds

**Example:**
```ruby
all_agents do
  timeout 180
end
```

---

### parameters

Set default LLM parameters for all agents.

**Signature:**
```ruby
parameters(params) → void
```

**Parameters:**
- `params` (Hash, required): LLM parameters

**Example:**
```ruby
all_agents do
  parameters temperature: 0.7, max_tokens: 2000
end
```

---

### headers

Set default HTTP headers for all agents.

**Signature:**
```ruby
headers(header_hash) → void
```

**Parameters:**
- `header_hash` (Hash, required): HTTP headers

**Example:**
```ruby
all_agents do
  headers "X-Organization" => "org123"
end
```

---

### coding_agent

Set default coding_agent flag for all agents.

**Signature:**
```ruby
coding_agent(enabled) → void
```

**Parameters:**
- `enabled` (Boolean, required): Include base prompt

**Example:**
```ruby
all_agents do
  coding_agent false
end
```

---

### tools

Add tools that all agents will have.

**Signature:**
```ruby
tools(*tool_names) → void
```

**Parameters:**
- `tool_names` (Symbol, variadic): Tool names

**Example:**
```ruby
all_agents do
  tools :Read, :Write
end
```

---

### permissions

Configure permissions for all agents.

**Signature:**
```ruby
permissions(&block) → void
```

**Parameters:**
- `block` (required): Permissions configuration block

**Example:**
```ruby
all_agents do
  permissions do
    tool(:Write).deny_paths "secrets/**"
    tool(:Bash).deny_commands "^rm -rf"
  end
end
```

---

### hook

Add hook for all agents.

**Signature:**
```ruby
hook(event, matcher: nil, command: nil, timeout: nil, &block) → void
```

**Parameters:** Same as agent-level `hook`

**Valid events:** All agent-level events (not swarm-level events)

**Example:**
```ruby
all_agents do
  hook :pre_tool_use, matcher: "Write" do |ctx|
    # Validation for all agents
  end
end
```

---

## Permissions Builder DSL

Methods available in the `permissions` block.

### tool

Get a tool permissions proxy for configuring a specific tool.

**Signature:**
```ruby
tool(tool_name) → ToolPermissionsProxy
```

**Parameters:**
- `tool_name` (Symbol, required): Tool name

**Returns:** `ToolPermissionsProxy` with fluent methods

**Example:**
```ruby
permissions do
  tool(:Write).allow_paths("src/**/*").deny_paths("src/secrets/**")
  tool(:Read).deny_paths("config/credentials.yml")
  tool(:Bash).allow_commands("^git status$")
end
```

---

### allow_paths

Add allowed path patterns (chainable).

**Signature:**
```ruby
allow_paths(*patterns) → self
```

**Parameters:**
- `patterns` (String, variadic): Glob patterns

**Returns:** `self` (for chaining)

**Example:**
```ruby
tool(:Write).allow_paths("backend/**/*")
tool(:Write).allow_paths("frontend/**/*", "shared/**/*")
```

---

### deny_paths

Add denied path patterns (chainable).

**Signature:**
```ruby
deny_paths(*patterns) → self
```

**Parameters:**
- `patterns` (String, variadic): Glob patterns

**Returns:** `self` (for chaining)

**Example:**
```ruby
tool(:Write).deny_paths("backend/secrets/**")
tool(:Read).deny_paths("config/credentials.yml", ".env")
```

---

### allow_commands

Add allowed command patterns (Bash tool only, chainable).

**Signature:**
```ruby
allow_commands(*patterns) → self
```

**Parameters:**
- `patterns` (String, variadic): Regex patterns

**Returns:** `self` (for chaining)

**Example:**
```ruby
tool(:Bash).allow_commands("^git (status|diff|log)$")
tool(:Bash).allow_commands("^npm test$", "^bundle exec rspec$")
```

---

### deny_commands

Add denied command patterns (Bash tool only, chainable).

**Signature:**
```ruby
deny_commands(*patterns) → self
```

**Parameters:**
- `patterns` (String, variadic): Regex patterns

**Returns:** `self` (for chaining)

**Example:**
```ruby
tool(:Bash).deny_commands("^rm -rf")
tool(:Bash).deny_commands("^sudo", "^dd if=")
```

---

## Node Builder DSL

Methods available in the `node` block.

### agent

Configure an agent for this node (returns fluent config object).

**Signature:**
```ruby
agent(name, reset_context: true) → AgentConfig
```

**Parameters:**
- `name` (Symbol, required): Agent name
- `reset_context` (Boolean, keyword, optional): Whether to reset conversation context
  - `true` (default): Fresh context for each node execution
  - `false`: Preserve conversation history from previous nodes

**Returns:** `AgentConfig` with `.delegates_to(*names)` method

**Example:**
```ruby
# Fresh context (default)
agent(:backend)

# Preserve context from previous nodes
agent(:backend, reset_context: false).delegates_to(:tester)

# Without delegation, preserving context
agent(:planner, reset_context: false)
```

**When to use `reset_context: false`:**
- Iterative refinement workflows
- Agent needs to remember previous node conversations
- Chain of thought reasoning across stages
- Self-reflection or debate loops

**When to use `reset_context: true` (default):**
- Independent validation or fresh perspective
- Memory management in long workflows
- Different roles for same agent in different stages

---

### depends_on

Declare node dependencies (prerequisite nodes).

**Signature:**
```ruby
depends_on(*node_names) → void
```

**Parameters:**
- `node_names` (Symbol, variadic): Names of prerequisite nodes

**Example:**
```ruby
depends_on :planning
depends_on :frontend, :backend  # Multiple dependencies
```

---

### lead

Override the lead agent for this node.

**Signature:**
```ruby
lead(agent_name) → void
```

**Parameters:**
- `agent_name` (Symbol, required): Lead agent name

**Default:** First agent in node

**Example:**
```ruby
agent(:backend).delegates_to(:tester)
agent(:tester)
lead :tester  # Make tester the lead instead of backend
```

---

### input

Define input transformer (Ruby block).

**Signature:**
```ruby
input(&block) → void
```

**Parameters:**
- `block` (required): Transformer block, receives `NodeContext`

**Block return values:**
- `String`: Transformed input content
- `Hash`: `{ skip_execution: true, content: "..." }` to skip node

**Context methods:**
- `ctx.content`: Previous node's content (convenience)
- `ctx.original_prompt`: Original user prompt
- `ctx.all_results[:node_name]`: Access any previous node
- `ctx.node_name`: Current node name
- `ctx.dependencies`: Node dependencies

**Example:**
```ruby
input do |ctx|
  previous = ctx.content
  "Task: #{ctx.original_prompt}\nPrevious: #{previous}"
end

# Access specific nodes
input do |ctx|
  plan = ctx.all_results[:planning].content
  design = ctx.all_results[:design].content
  "Implement:\nPlan: #{plan}\nDesign: #{design}"
end

# Skip execution (caching)
input do |ctx|
  cached = check_cache(ctx.content)
  if cached
    { skip_execution: true, content: cached }
  else
    ctx.content
  end
end
```

---

### input_command

Define input transformer (Bash command).

**Signature:**
```ruby
input_command(command, timeout: 60) → void
```

**Parameters:**
- `command` (String, required): Bash command
- `timeout` (Integer, keyword): Timeout in seconds

**Input:** NodeContext as JSON on stdin

**Exit codes:**
- `0`: Success, use stdout as transformed content
- `1`: Skip node execution, use current_input unchanged
- `2`: Halt workflow with error from stderr

**Example:**
```ruby
input_command "scripts/validate.sh", timeout: 30
input_command "jq '.content'"
```

---

### output

Define output transformer (Ruby block).

**Signature:**
```ruby
output(&block) → void
```

**Parameters:**
- `block` (required): Transformer block, receives `NodeContext`

**Block return value:**
- `String`: Transformed output content

**Context methods:**
- `ctx.content`: Current node's result content (convenience)
- `ctx.original_prompt`: Original user prompt
- `ctx.all_results[:node_name]`: Access any completed node
- `ctx.node_name`: Current node name

**Example:**
```ruby
output do |ctx|
  # Side effect: save to file
  File.write("results/plan.txt", ctx.content)

  # Return transformed output
  "Key decisions: #{extract_decisions(ctx.content)}"
end

# Access multiple nodes
output do |ctx|
  plan = ctx.all_results[:planning].content
  impl = ctx.content
  "Completed:\nPlan: #{plan}\nImpl: #{impl}"
end
```

---

### output_command

Define output transformer (Bash command).

**Signature:**
```ruby
output_command(command, timeout: 60) → void
```

**Parameters:**
- `command` (String, required): Bash command
- `timeout` (Integer, keyword): Timeout in seconds

**Input:** NodeContext as JSON on stdin

**Exit codes:**
- `0`: Success, use stdout as transformed content
- `1`: Pass through unchanged, use result.content
- `2`: Halt workflow with error from stderr

**Example:**
```ruby
output_command "scripts/format.sh", timeout: 30
output_command "tee results.txt"
```

---

## Execution Methods

### swarm.execute

Execute a task using the lead agent.

**Signature:**
```ruby
swarm.execute(prompt, &block) → Result
```

**Parameters:**
- `prompt` (String, required): Task prompt
- `block` (optional): Log entry handler for streaming

**Returns:** `Result` object

**Example:**
```ruby
# Basic execution
result = swarm.execute("Build a REST API")

# With logging
result = swarm.execute("Build a REST API") do |log_entry|
  puts "#{log_entry[:type]}: #{log_entry[:agent]}" if log_entry[:type] == "tool_call"
end

# Check result
if result.success?
  puts result.content
  puts "Cost: $#{result.total_cost}"
  puts "Tokens: #{result.total_tokens}"
  puts "Duration: #{result.duration}s"
else
  puts "Error: #{result.error.message}"
end
```

---

## Result Object

Returned by `swarm.execute`.

### Attributes

**content**
```ruby
result.content → String | nil
```
Final response content from the swarm.

**agent**
```ruby
result.agent → String
```
Name of the agent that produced the final response.

**duration**
```ruby
result.duration → Float
```
Total execution duration in seconds.

**logs**
```ruby
result.logs → Array<Hash>
```
Array of log entries (events during execution).

**error**
```ruby
result.error → Exception | nil
```
Error object if execution failed, nil otherwise.

---

### Methods

**success?**
```ruby
result.success? → Boolean
```
Returns true if execution succeeded (no error).

**failure?**
```ruby
result.failure? → Boolean
```
Returns true if execution failed (has error).

**total_cost**
```ruby
result.total_cost → Float
```
Total cost in dollars across all LLM calls.

**total_tokens**
```ruby
result.total_tokens → Integer
```
Total tokens used (input + output).

**agents_involved**
```ruby
result.agents_involved → Array<Symbol>
```
List of all agents that participated.

**llm_requests**
```ruby
result.llm_requests → Integer
```
Number of LLM API calls made.

**tool_calls_count**
```ruby
result.tool_calls_count → Integer
```
Number of tool calls made.

**to_h**
```ruby
result.to_h → Hash
```
Convert to hash representation.

**to_json**
```ruby
result.to_json → String
```
Convert to JSON string.

---

## Context Management

SwarmSDK automatically manages conversation context to prevent hitting token limits while preserving accuracy.

### Automatic Features

#### Ephemeral System Reminders

System reminders (guidance, tool lists, error recovery) are sent to the LLM but **NOT persisted** in conversation history. This prevents reminder accumulation and saves 80-95% of reminder tokens in long conversations.

**How it works:**
```
Turn 1: Sends reminders → LLM sees them → NOT stored in history
Turn 2: Sends new reminders → LLM sees only current turn's reminders
Turn 20: No accumulated reminders (saves 1,200-13,800 tokens!)
```

**Automatic** - No configuration needed. All `<system-reminder>` blocks are extracted and sent ephemerally.

#### Automatic Compression (60% Threshold)

When context usage reaches **60%**, SwarmSDK automatically compresses old tool results to free space.

**What gets compressed:**
- ✅ **Tool results** (`role: :tool`) older than 10 messages
- ✅ **Long outputs** from Read, Bash, Grep, etc.
- ❌ **User messages** - Never compressed (user intent preserved)
- ❌ **Assistant messages** - Never compressed (reasoning preserved)
- ❌ **Recent messages** (last 10) - Full detail maintained

**Progressive compression by age:**
```
Age 11-20 messages:  → 1000 chars max (light)
Age 21-40 messages:  → 500 chars max (moderate)
Age 41-60 messages:  → 200 chars max (heavy)
Age 61+ messages:    → 100 chars max (minimal summary)
```

**Triggers:**
- Automatically at 60% context usage
- Only once (doesn't re-compress)
- Logs `context_compression` event

**Example log:**
```json
{
  "type": "context_compression",
  "agent": "assistant",
  "total_messages": 45,
  "messages_compressed": 12,
  "tokens_before": 95000,
  "current_usage": "61%",
  "compression_strategy": "progressive_tool_result_compression",
  "keep_recent": 10
}
```

**Token savings:**
- Typical: 10,000-20,000 tokens freed
- Heavy tool usage: 30,000-50,000 tokens freed
- Extends conversation by 20-40% more turns

### Context Warning Thresholds

SwarmSDK emits warnings at these thresholds:
- **60%** - Triggers automatic compression
- **80%** - Informational warning (approaching limit)
- **90%** - Critical warning (near limit)

Each threshold emits once via `context_limit_warning` event.

### Impact on Accuracy

**Minimal** - Compression is designed to preserve accuracy:
1. Recent context (last 10 messages) unchanged
2. Conversational flow preserved (user/assistant messages)
3. Tool results compressed but essential structure kept
4. Progressive (older = more compressed)
5. Only triggers when needed (60% full)

**When it might impact accuracy:**
- Agent references very old tool results (rare)
- Multi-file analysis across 40+ turns (uncommon)

**When it doesn't impact accuracy:**
- Short conversations (<30 turns)
- Recent tool results (always full detail)
- User/assistant conversation (never compressed)

### Manual Control

Context management is automatic, but you can monitor via events:

```ruby
swarm = SwarmSDK.build do
  name "My Swarm"

  on :context_limit_warning do |ctx|
    puts "Context at #{ctx.metadata[:current_usage]}"
  end

  on :context_compression do |ctx|
    puts "Compressed #{ctx.metadata[:messages_compressed]} messages"
  end
end
```

---

## Hook Context Methods

Available in hook blocks via the `ctx` parameter.

### Context Attributes

**event**
```ruby
ctx.event → Symbol
```
Current event type.

**agent_name**
```ruby
ctx.agent_name → String
```
Current agent name.

**tool_call**
```ruby
ctx.tool_call → ToolCall
```
Tool call object (for tool events).

**tool_result**
```ruby
ctx.tool_result → ToolResult
```
Tool result object (for post_tool_use).

**delegation_target**
```ruby
ctx.delegation_target → Symbol
```
Target agent name (for delegation events).

**metadata**
```ruby
ctx.metadata → Hash
```
Additional event metadata (read-write).

**swarm**
```ruby
ctx.swarm → Swarm
```
Reference to the swarm instance.

---

### Context Methods

**tool_event?**
```ruby
ctx.tool_event? → Boolean
```
Returns true if event is pre_tool_use or post_tool_use.

**delegation_event?**
```ruby
ctx.delegation_event? → Boolean
```
Returns true if event is pre_delegation or post_delegation.

**tool_name**
```ruby
ctx.tool_name → String | nil
```
Tool name (convenience method).

---

### Action Methods

**halt**
```ruby
ctx.halt(message) → HookResult
```
Halt execution and return error message.

**replace**
```ruby
ctx.replace(value) → HookResult
```
Replace tool result or prompt with custom value.

**reprompt**
```ruby
ctx.reprompt(prompt) → HookResult
```
Reprompt the agent with a new prompt (swarm_stop only).

**finish_agent**
```ruby
ctx.finish_agent(message) → HookResult
```
Finish current agent's execution with final message.

**finish_swarm**
```ruby
ctx.finish_swarm(message) → HookResult
```
Finish entire swarm execution with final message.

**breakpoint**
```ruby
ctx.breakpoint → void
```
Enter interactive debugging (binding.irb).

---

### ToolCall Object

**Attributes:**
```ruby
tool_call.id → String            # Tool call ID
tool_call.name → String          # Tool name
tool_call.parameters → Hash      # Tool parameters
```

---

### ToolResult Object

**Attributes:**
```ruby
tool_result.tool_call_id → String   # Tool call ID
tool_result.tool_name → String      # Tool name
tool_result.content → String        # Result content
tool_result.success? → Boolean      # Success status
```

---

## NodeContext Methods

Available in node transformer blocks via the `ctx` parameter.

### Attributes

**original_prompt**
```ruby
ctx.original_prompt → String
```
Original user prompt for the workflow.

**all_results**
```ruby
ctx.all_results → Hash<Symbol, Result>
```
Results from all completed nodes.

**node_name**
```ruby
ctx.node_name → Symbol
```
Current node name.

**dependencies**
```ruby
ctx.dependencies → Array<Symbol>
```
Node dependencies (input transformers only).

---

### Convenience Methods

**content**
```ruby
ctx.content → String | nil
```
- Input transformers: Previous node's content (or transformed content)
- Output transformers: Current node's content

**agent**
```ruby
ctx.agent → String | nil
```
Agent name from previous_result or result.

**logs**
```ruby
ctx.logs → Array | nil
```
Logs from previous_result or result.

**duration**
```ruby
ctx.duration → Float | nil
```
Duration from previous_result or result.

**error**
```ruby
ctx.error → Exception | nil
```
Error from previous_result or result.

**success?**
```ruby
ctx.success? → Boolean | nil
```
Success status from previous_result or result.

---

### Control Flow Methods

Methods for dynamic workflow control (loops, conditional branching, early termination).

**goto_node**
```ruby
ctx.goto_node(node_name, content:) → Hash
```
Jump to a different node with custom content, bypassing normal dependency order.

**Parameters:**
- `node_name` (Symbol, required): Target node name
- `content` (String, required): Content to pass to target node (validated non-nil)

**Returns:** Control hash (processed by NodeOrchestrator)

**Valid in:** Both input and output transformers

**Example:**
```ruby
output do |ctx|
  if needs_revision?(ctx.content)
    # Jump back to revision node
    ctx.goto_node(:revision, content: ctx.content)
  else
    ctx.content  # Continue to next node normally
  end
end
```

**Use cases:**
- Implementing loops in workflows
- Conditional branching based on results
- Dynamic workflow routing
- Retry logic

**halt_workflow**
```ruby
ctx.halt_workflow(content:) → Hash
```
Stop entire workflow execution immediately and return content as final result.

**Parameters:**
- `content` (String, required): Final content to return (validated non-nil)

**Returns:** Control hash (processed by NodeOrchestrator)

**Valid in:** Both input and output transformers

**Example:**
```ruby
output do |ctx|
  if converged?(ctx.content)
    # Stop workflow early
    ctx.halt_workflow(content: ctx.content)
  else
    ctx.content  # Continue to next node
  end
end
```

**Use cases:**
- Early termination on success
- Error handling and bailout
- Loop termination conditions
- Convergence checks

**skip_execution**
```ruby
ctx.skip_execution(content:) → Hash
```
Skip LLM execution for current node and use provided content instead.

**Parameters:**
- `content` (String, required): Content to use instead of LLM execution (validated non-nil)

**Returns:** Control hash (processed by NodeOrchestrator)

**Valid in:** Input transformers only

**Example:**
```ruby
input do |ctx|
  cached = check_cache(ctx.content)
  if cached
    # Skip expensive LLM call
    ctx.skip_execution(content: cached)
  else
    ctx.content  # Execute node normally
  end
end
```

**Use cases:**
- Caching node results
- Conditional execution
- Performance optimization
- Validation checks

**Error Handling with Control Flow:**

All control flow methods validate that content is not nil. If a node fails, check for errors:

```ruby
output do |ctx|
  if ctx.error
    # Don't try to continue with nil content
    ctx.halt_workflow(content: "Error: #{ctx.error.message}")
  else
    ctx.goto_node(:next_node, content: ctx.content)
  end
end
```

---

## Complete Example

```ruby
#!/usr/bin/env ruby
require "swarm_sdk"

swarm = SwarmSDK.build do
  name "Code Review Team"
  lead :reviewer

  # Apply settings to all agents
  all_agents do
    provider :anthropic
    timeout 180
    coding_agent false

    permissions do
      tool(:Write).deny_paths "secrets/**"
    end
  end

  # Lead reviewer agent
  agent :reviewer do
    model "claude-sonnet-4"
    description "Lead code reviewer coordinating the review process"
    directory "."

    system_prompt <<~PROMPT
      You are a lead code reviewer. Coordinate the review process:
      1. Delegate security checks to the security expert
      2. Delegate performance analysis to the performance expert
      3. Synthesize feedback into actionable recommendations
    PROMPT

    tools :Read, :Write, :Edit
    delegates_to :security, :performance

    hook :pre_delegation do |ctx|
      puts "Delegating to #{ctx.delegation_target}..."
    end
  end

  # Security expert
  agent :security do
    model "gpt-5"
    description "Security expert checking for vulnerabilities"

    system_prompt "You are a security expert. Check code for vulnerabilities, injection attacks, and security best practices."

    tools :Read, :Grep

    hook :pre_tool_use, matcher: "Read" do |ctx|
      # Log which files are being reviewed
      puts "Reviewing: #{ctx.tool_call.parameters[:file_path]}"
    end
  end

  # Performance expert
  agent :performance do
    model "gpt-5"
    description "Performance expert analyzing efficiency"

    system_prompt "You are a performance expert. Analyze code for performance issues, algorithmic complexity, and optimization opportunities."

    tools :Read, :Grep, :Bash

    permissions do
      tool(:Bash).allow_commands "^(node --prof|ruby-prof|py-spy)"
    end
  end

  # Swarm-level hook
  hook :swarm_stop do |ctx|
    puts "\nReview complete!"
    puts "Duration: #{ctx.metadata[:duration]}s"
    puts "Cost: $#{ctx.metadata[:total_cost]}"
  end
end

# Execute review
result = swarm.execute("Review the authentication code in src/auth.rb") do |log|
  if log[:type] == "tool_call"
    puts "  #{log[:tool]}: #{log[:arguments].inspect}"
  end
end

# Check result
if result.success?
  puts "\nFeedback:"
  puts result.content

  puts "\nStats:"
  puts "  Agents: #{result.agents_involved.join(", ")}"
  puts "  Tokens: #{result.total_tokens}"
  puts "  Cost: $#{result.total_cost}"
else
  puts "Error: #{result.error.message}"
  exit 1
end
```

---

## See Also

- [YAML Reference](./yaml.md): Complete YAML configuration reference
- [CLI Reference](./cli.md): Command-line interface reference
- [Getting Started Guide](../guides/getting-started.md): Introduction to SwarmSDK
