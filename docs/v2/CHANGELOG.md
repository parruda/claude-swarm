# Changelog

All notable changes to SwarmSDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### 💥 BREAKING CHANGES

#### Node Dependencies: `after()` Renamed to `depends_on()`

**Breaking Change:** The `after()` method for declaring node dependencies has been renamed to `depends_on()` for clearer semantic meaning.

**Why This Matters:**
- `depends_on()` explicitly communicates dependency relationships
- More intuitive for users familiar with build tools (Make, Rake, etc.)
- Clearer intent: "this node depends on these nodes"

**Migration Required:**

```ruby
# OLD
node :implementation do
  after :planning  # ❌ Old name
end

# NEW
node :implementation do
  depends_on :planning  # ✅ New name
end

# Multiple dependencies
node :integration do
  depends_on :frontend, :backend  # ✅ Clearer than after
end
```

**YAML:**
```yaml
# OLD
nodes:
  implementation:
    after:
      - planning

# NEW
nodes:
  implementation:
    depends_on:
      - planning
```

**Migration:** Simple search-and-replace: `after` → `depends_on`

**Commit:** d0e98d7 "Add bash command transformers with exit code control"

### Added

#### Bash Command Transformers for Node Workflows

Added external bash script transformers for node input/output transformation with clean exit code semantics.

**What's New:**

Node transformers can now be **external bash commands** (not just Ruby blocks), enabling:
- YAML-only workflows (no Ruby code required)
- Integration with existing bash scripts and CLI tools
- Simple validation, caching, and formatting scripts
- Language-agnostic transformation logic

**Ruby DSL:**
```ruby
node :validation do
  # Input transformer as bash command
  input_command("scripts/validate.sh", timeout: 30)

  # Output transformer as bash command
  output_command("scripts/format.sh")

  depends_on :planning
end
```

**YAML:**
```yaml
nodes:
  validation:
    input_command:
      command: "scripts/validate.sh"
      timeout: 30
    output_command:
      command: "scripts/format.sh"
      timeout: 60  # default
    depends_on:
      - planning
```

**Exit Code Semantics:**

Bash transformers use exit codes for clean control flow:

| Exit Code | Behavior | STDOUT | STDERR | Use Case |
|-----------|----------|--------|--------|----------|
| **0** | Success | Used as content | Logged | Transform and continue |
| **1** | Skip execution | **IGNORED** | Logged | Caching, conditional skip |
| **2** | Halt workflow | **IGNORED** | Error message | Validation failure |

**Exit 0: Transform Success**
```bash
#!/bin/bash
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.content')

# Validate
if [ ${#CONTENT} -lt 10 ]; then
    echo "ERROR: Too short" >&2
    exit 2
fi

# Transform
echo "Validated: $CONTENT"
exit 0  # Success - use STDOUT
```

**Exit 1: Skip Node Execution**
```bash
#!/bin/bash
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.content')

# Check cache
if cached "$CONTENT"; then
    exit 1  # Skip node, use input unchanged (STDOUT ignored)
fi

echo "$CONTENT"
exit 0
```

**Exit 2: Halt Workflow**
```bash
#!/bin/bash
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.content')

if [ ${#CONTENT} -gt 10000 ]; then
    echo "ERROR: Content exceeds 10K limit" >&2
    exit 2  # Halt workflow with error
fi

echo "$CONTENT"
exit 0
```

**JSON Input (STDIN):**

Bash transformers receive NodeContext as JSON on STDIN:

```json
{
  "event": "input",
  "node": "implementation",
  "original_prompt": "Build auth API",
  "content": "PLAN: Create endpoints...",
  "all_results": {
    "planning": {
      "content": "Create endpoints...",
      "agent": "planner",
      "duration": 2.5,
      "success": true
    }
  },
  "dependencies": ["planning"]
}
```

**Access All Fields:**
```bash
#!/bin/bash
INPUT=$(cat)

# Parse JSON with jq
CONTENT=$(echo "$INPUT" | jq -r '.content')
ORIGINAL=$(echo "$INPUT" | jq -r '.original_prompt')
PLAN=$(echo "$INPUT" | jq -r '.all_results.planning.content')

# Combine context
cat <<EOF
ORIGINAL REQUEST: $ORIGINAL
PLAN: $PLAN
CURRENT: $CONTENT

Now implement.
EOF

exit 0
```

**Environment Variables:**

| Variable | Description |
|----------|-------------|
| `SWARM_SDK_PROJECT_DIR` | Project root directory |
| `SWARM_SDK_NODE_NAME` | Current node name |
| `PATH` | System PATH |

**Key Features:**

1. **Exit Code Control Flow** - Clean semantics (0=success, 1=skip, 2=halt)
2. **Rich Context Access** - Full NodeContext as JSON on STDIN
3. **Environment Variables** - Project path and node name available
4. **Timeout Support** - Configurable timeout (default 60s)
5. **YAML Compatible** - Works in both Ruby DSL and YAML workflows
6. **Ruby Block Compatible** - Mix bash commands and Ruby blocks freely

**Why This Matters:**

- **Reusability** - Use existing bash scripts and CLI tools
- **Simplicity** - No Ruby knowledge required for simple transformations
- **Integration** - Call linters, formatters, validators directly
- **YAML Workflows** - Define entire workflows in YAML without Ruby code
- **Clean Semantics** - Exit codes provide universal control flow

**Example: Caching with Exit 1**
```ruby
node :expensive_computation do
  agent(:ai_agent)

  # Skip if cached
  input_command("scripts/cache_check.sh")

  # Save to cache
  output_command("scripts/cache_save.sh")
end
```

`scripts/cache_check.sh`:
```bash
#!/bin/bash
INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.content')
CACHE_KEY=$(echo -n "$CONTENT" | md5)

if [ -f "cache/$CACHE_KEY" ]; then
    # Cache hit - skip expensive LLM call
    exit 1
fi

# No cache - proceed with LLM
echo "$CONTENT"
exit 0
```

**Technical Details:**

- `lib/swarm_sdk/node/transformer_executor.rb` - NEW: TransformerExecutor class
- `lib/swarm_sdk/node/builder.rb` - NEW: `input_command()`, `output_command()` methods
- Uses `Open3.capture3` for process execution
- JSON generation via `build_transformer_input()`
- Timeout handling with `Timeout.timeout`
- Comprehensive test coverage: 21 new tests in `test/swarm_sdk/node_bash_transformers_test.rb`

**Documentation:**

- [docs/v2/architecture/bash-transformers.md](architecture/bash-transformers.md) - Architecture with Mermaid diagrams
- [docs/v2/guides/bash-transformers-101.md](guides/bash-transformers-101.md) - Beginner tutorial
- [docs/v2/api/sdk/transformer-executor.md](api/sdk/transformer-executor.md) - API reference
- [NODE_WORKFLOWS.md](../../NODE_WORKFLOWS.md#bash-command-transformers-yaml--dsl) - Updated with bash examples

**Commits:**
- d0e98d7 "Add bash command transformers with exit code control for node workflows"
- 99f1af4 "update test" (hook definition tests)

**See Also:**
- [Bash Transformers Architecture](architecture/bash-transformers.md) - Deep dive with diagrams
- [Bash Transformers Tutorial](guides/bash-transformers-101.md) - Getting started guide
- [TransformerExecutor API](api/sdk/transformer-executor.md) - Complete API reference

---

## [2.1.0] - 2025-10-15

### 💥 BREAKING CHANGES

#### Node Transformers Now Receive NodeContext Instead of Result/Hash

**Breaking Change:** Input and output transformers now receive a `NodeContext` object instead of raw `Result` or `Hash` objects. This provides unified access to the original prompt, all previous results, and rich metadata.

**Why This Matters:**
- Access `original_prompt` from ANY node in your workflow
- Query results from specific previous nodes via `all_results[:node_name]`
- Cleaner API with convenience accessors (`ctx.content`, `ctx.agent`, etc.)
- Consistent interface across all transformers

**Migration Required:**

```ruby
# OLD (v2.0.x) - Transformers received Result or Hash
node :implementation do
  after :planning

  input do |previous_result|
    # ❌ No access to original prompt
    # ❌ Can't access other nodes beyond immediate predecessor
    previous_result.content
  end

  output do |result|
    result.content
  end
end

# NEW (v2.1.0) - Transformers receive NodeContext
node :implementation do
  after :planning

  input do |ctx|
    # ✅ Access original prompt from any node
    # ✅ Access any previous node via all_results
    # ✅ Convenience accessor for content

    <<~PROMPT
      ORIGINAL REQUEST: #{ctx.original_prompt}
      PLAN: #{ctx.all_results[:planning].content}

      Please implement.
    PROMPT
  end

  output do |ctx|
    # ✅ Same unified interface
    "IMPLEMENTATION: #{ctx.content}"
  end
end
```

**NodeContext API:**
- `ctx.content` - Convenience accessor for current/previous node content
- `ctx.original_prompt` - Original user prompt (available in ALL nodes)
- `ctx.all_results` - Hash of all previous node results (`ctx.all_results[:node_name]`)
- `ctx.node_name` - Current node's name
- `ctx.dependencies` - List of dependency nodes (input transformers only)
- `ctx.result` - Current Result object (output transformers only)
- `ctx.previous_result` - Previous Result object (input transformers only)
- `ctx.agent`, `ctx.logs`, `ctx.duration`, `ctx.error`, `ctx.success?` - Metadata accessors

**See:** `lib/swarm_sdk/node_context.rb:1-170` for complete API documentation.

#### Agent Configuration: `skip_base_prompt` Renamed to `coding_agent`

**Breaking Change:** The `skip_base_prompt` configuration field has been renamed to `coding_agent` for clearer semantic meaning.

**Why This Matters:**
- `coding_agent: true` clearly indicates the agent includes coding-specific base prompt
- `coding_agent: false` (default) indicates a specialized agent with custom-only prompt
- Better describes intent than the negative "skip" terminology

**Migration Required:**

```yaml
# OLD (v2.0.x)
agents:
  backend:
    description: "Backend developer"
    skip_base_prompt: false  # ❌ Old name
    system_prompt: "You build APIs"

# NEW (v2.1.0)
agents:
  backend:
    description: "Backend developer"
    coding_agent: false  # ✅ New name (default, can omit)
    system_prompt: "You build APIs"
```

```ruby
# OLD DSL (v2.0.x)
agent :backend do
  skip_base_prompt true  # ❌ Old name
end

# NEW DSL (v2.1.0)
agent :backend do
  coding_agent true  # ✅ New name
end
```

**Defaults:**
- `coding_agent: false` (default) - Use only custom prompt (most agents)
- `coding_agent: true` - Include base coding prompt + custom prompt (coding/development agents)

**Updated Files:**
- All documentation files updated with new terminology
- Example files renamed: `examples/skip_base_prompt.yml` → `examples/coding_agent.yml`
- Tests renamed: `test/swarm_sdk/skip_base_prompt_test.rb` → `test/swarm_sdk/coding_agent_test.rb`

**See:**
- `docs/v2/user-guide/configuration/yaml-reference.md` - Updated YAML reference
- `docs/v2/api/sdk/agent-builder.md` - Updated DSL reference

### Added

#### NodeContext for Unified Transformer Context

Added `SwarmSDK::NodeContext` class that provides rich context information to node transformers.

**What's New:**

Every transformer (input and output) now receives a NodeContext with:

```ruby
node :implementation do
  after :planning, :design

  input do |ctx|
    # Original user prompt (available in ALL nodes!)
    ctx.original_prompt  # => "Build a REST API"

    # Access ANY previous node by name
    plan = ctx.all_results[:planning].content
    design = ctx.all_results[:design].content

    # Convenience accessor for content
    ctx.content  # Previous node's content (or nil for multiple deps)

    # Current node metadata
    ctx.node_name        # => :implementation
    ctx.dependencies     # => [:planning, :design]

    # Result metadata
    ctx.agent           # Previous agent name
    ctx.logs            # Previous node's logs
    ctx.duration        # Previous node's duration

    "Implement based on:\nPlan: #{plan}\nDesign: #{design}"
  end

  output do |ctx|
    # Same rich context in output transformers
    ctx.content          # This node's result content
    ctx.original_prompt  # Original user prompt
    ctx.all_results      # All completed nodes
    ctx.node_name        # This node's name

    "IMPLEMENTATION: #{ctx.content}"
  end
end
```

**Key Features:**

1. **Original Prompt Access** - Every node can access the original user prompt
2. **Full Workflow Visibility** - Query any previous node's result via `all_results`
3. **Convenience Accessors** - Simple `ctx.content` for common case
4. **Rich Metadata** - Access agent, logs, duration, errors from any result
5. **Type Safety** - Single, well-documented context type for all transformers
6. **Nil Handling** - `ctx.content` returns `nil` for multiple dependencies (use `all_results` instead)

**Example Use Cases:**

```ruby
# Include original context in final review
node :review do
  input do |ctx|
    <<~PROMPT
      ORIGINAL REQUEST: #{ctx.original_prompt}
      IMPLEMENTATION: #{ctx.all_results[:implementation].content}

      Does this meet requirements?
    PROMPT
  end
end

# Aggregate results from multiple nodes
node :integration do
  after :frontend, :backend

  input do |ctx|
    frontend = ctx.all_results[:frontend].content
    backend = ctx.all_results[:backend].content

    "Integrate:\nFrontend: #{frontend}\nBackend: #{backend}"
  end
end

# Save to file with full context
node :implementation do
  output do |ctx|
    # Side effect: save with original prompt as header
    File.write("results.txt", <<~CONTENT)
      Task: #{ctx.original_prompt}
      Result: #{ctx.content}
      Agent: #{ctx.agent}
      Duration: #{ctx.duration}s
    CONTENT

    ctx.content  # Return for next node
  end
end
```

**Technical Details:**
- `lib/swarm_sdk/node_context.rb:1-170` - NodeContext implementation
- `lib/swarm_sdk/node_orchestrator.rb` - NodeContext integration
- `test/swarm_sdk/node_context_test.rb:1-358` - Comprehensive test coverage (9 tests)

**See:**
- [NODE_WORKFLOWS.md](../../NODE_WORKFLOWS.md#inputoutput-transformers-with-nodecontext) - Complete guide with examples
- `examples/node_context_demo.rb` - Working demonstration

#### Auto-Add Delegation for Cleaner Node Configuration

Agents mentioned in `delegates_to` are now **automatically added** to the node. You no longer need to explicitly declare leaf agents.

**What's New:**

```ruby
# OLD (v2.0.x) - Manual declaration of all agents
node :implementation do
  agent(:backend).delegates_to(:tester, :database)
  agent(:tester).delegates_to(:database)
  agent(:database)  # ❌ Must declare leaf explicitly
end

# NEW (v2.1.0) - Auto-add makes this cleaner
node :implementation do
  agent(:backend).delegates_to(:tester, :database)
  agent(:tester).delegates_to(:database)
  # ✅ database auto-added (no declaration needed)
end

# Even simpler for single delegation
node :implementation do
  agent(:backend).delegates_to(:tester)
  # ✅ tester auto-added automatically
end
```

**When to Explicitly Declare:**

Only declare agents that have their own delegation:

```ruby
node :complex do
  # Declare agents WITH delegation
  agent(:lead).delegates_to(:backend, :frontend)
  agent(:backend).delegates_to(:database)

  # Auto-added (no declaration needed):
  # - frontend (mentioned in lead's delegates_to, no own delegation)
  # - database (mentioned in backend's delegates_to, no own delegation)
end
```

**How It Works:**

1. Parser collects all agents mentioned in `delegates_to` across the node
2. Finds agents that aren't explicitly declared
3. Auto-adds them with empty delegation (`delegates_to: []`)
4. Validation ensures all agents exist in swarm-level configuration

**Why This Matters:**
- **Less Boilerplate** - Don't repeat agent names unnecessarily
- **Clearer Intent** - Only declare agents with delegation chains
- **Fewer Errors** - Can't forget to add leaf agents
- **Better Readability** - Focus on delegation structure, not declarations

**Technical Details:**
- `lib/swarm_sdk/node/builder.rb:273-296` - Auto-add implementation
- Runs during `validate!` phase before node execution
- Test coverage in `test/swarm_sdk/node_orchestrator_test.rb` (2 tests)

**See:**
- [NODE_WORKFLOWS.md](../../NODE_WORKFLOWS.md#agents-in-nodes) - Updated agent configuration guide

#### Node Log Events for Workflow Observability

Added `node_start` and `node_stop` log events for tracking workflow execution progress.

**What's New:**

NodeOrchestrator now emits events at node boundaries:

```ruby
swarm.execute("Build feature") do |log|
  case log[:type]
  when "node_start"
    # Emitted when node begins execution
    puts "Starting node: #{log[:node]}"
    puts "  Agents: #{log[:agents].join(', ')}"
    puts "  Dependencies: #{log[:dependencies].join(', ')}"
    puts "  Agent-less: #{log[:agent_less]}"  # Pure computation?

  when "node_stop"
    # Emitted when node completes
    puts "Completed node: #{log[:node]}"
    puts "  Duration: #{log[:duration]}s"
    puts "  Skipped: #{log[:skipped]}"  # Was execution skipped?
    puts "  Agents: #{log[:agents].join(', ')}"
  end
end
```

**Event Schema:**

**`node_start`** - When node begins:
```ruby
{
  type: "node_start",
  node: "planning",              # Node name (Symbol as String)
  agent_less: false,             # Whether node has agents
  agents: ["architect"],         # Agent names in this node
  dependencies: [],              # Prerequisite nodes
  timestamp: "2025-10-15T10:30:00Z"
}
```

**`node_stop`** - When node completes:
```ruby
{
  type: "node_stop",
  node: "planning",
  agent_less: false,
  skipped: false,                # Whether execution was skipped
  agents: ["architect"],
  duration: 12.5,                # Execution time (seconds)
  timestamp: "2025-10-15T10:30:12Z"
}
```

**Example: CLI Progress Display**

```ruby
swarm.execute("Build API") do |log|
  case log[:type]
  when "node_start"
    type = log[:agent_less] ? "Computation" : "LLM"
    puts "#{type} Node: #{log[:node]} starting..."

  when "node_stop"
    if log[:skipped]
      puts "  ⏭️  Skipped (cached/validation) in #{log[:duration]}s"
    elsif log[:agent_less]
      puts "  ✅ Computed in #{log[:duration]}s"
    else
      puts "  ✅ Completed in #{log[:duration]}s"
    end
  end
end
```

**Why This Matters:**
- **Visibility** - Track workflow progress through stages
- **Performance** - Measure time spent in each node
- **Debugging** - Identify slow or failing nodes
- **Observability** - Log node execution for monitoring
- **Skip Detection** - Know when nodes are bypassed (caching, validation)

**Technical Details:**
- `lib/swarm_sdk/node_orchestrator.rb` - Event emission
- `lib/swarm_cli/formatters/human_formatter.rb` - CLI display (planned)
- Available to all formatters (JSON, custom)

**See:**
- [NODE_WORKFLOWS.md](../../NODE_WORKFLOWS.md#node-log-events) - Complete event documentation

### Changed

#### Documentation Updates

All documentation and examples updated to reflect new terminology and APIs:

- **Terminology**: All references to `skip_base_prompt` updated to `coding_agent`
- **Examples**: Node workflow examples updated with NodeContext usage
- **API Docs**: Agent builder and definition docs updated
- **Guides**: Configuration guides updated with new field names

**Files Updated:**
- `docs/v2/api/sdk/agent-builder.md` - coding_agent terminology
- `docs/v2/api/sdk/agent-definition.md` - coding_agent field
- `docs/v2/guides/agent-configuration.md` - Updated configuration guide
- `docs/v2/user-guide/configuration/yaml-reference.md` - YAML reference
- `docs/v2/user-guide/ruby-dsl/agent-definition.md` - DSL reference
- `docs/v2/user-guide/ruby-dsl/dsl-reference.md` - DSL reference
- `NODE_WORKFLOWS.md` - Updated with NodeContext examples and auto-add delegation
- `examples/coding_agent.yml` - Renamed from skip_base_prompt.yml
- `examples/node_context_demo.rb` - New demonstration of NodeContext
- `examples/node_workflow.rb` - Updated with NodeContext
- `examples/ruby_dsl_skip_base_prompt.rb` - Updated for coding_agent
- `examples/v2/dsl/05_advanced_flags.rb` - Updated flags
- `examples/v2/simple-swarm-v2.rb` - Updated example

### Improved

#### CLI Spinner Display for Node Execution

SwarmCLI now displays progress spinners for node execution with clear visual feedback:

- `node_start` events show node beginning execution
- `node_stop` events show completion with duration
- Agent-less (computation) nodes clearly distinguished from LLM nodes
- Skip detection shows when nodes are bypassed

**Technical Details:**
- `lib/swarm_cli/formatters/human_formatter.rb` - Spinner integration
- `lib/swarm_cli/ui/state/spinner_manager.rb` - Node spinner lifecycle

### Internal

#### Test Coverage for NodeContext

Added comprehensive test suite for NodeContext functionality:

- 9 new tests in `test/swarm_sdk/node_context_test.rb`
- Tests cover all NodeContext accessors and edge cases
- Tests validate `original_prompt` access from all nodes
- Tests validate `all_results` hash with multiple dependencies
- Tests validate convenience accessors (content, agent, logs, etc.)
- Tests validate metadata access (node_name, dependencies)
- 358 lines of test code ensuring reliability

**Total Test Suite:**
- 802 tests, 2,325 assertions, all passing
- Zero RuboCop offenses
- Clean test output (no console pollution)

#### Documentation Quality

- Updated 260 lines in NODE_WORKFLOWS.md with NodeContext examples
- Added comprehensive inline documentation to NodeContext class
- Updated all API documentation with breaking change warnings
- Added migration guides with before/after examples

### Summary

**Version 2.1.0** is a significant enhancement to node-based workflows with **two breaking changes**:

1. **NodeContext API** - Transformers now receive rich context objects instead of raw Result/Hash
2. **Terminology Change** - `skip_base_prompt` renamed to `coding_agent`

**New Capabilities:**
- Access original prompt from any node in workflow
- Query any previous node's result by name
- Auto-add delegation for cleaner configuration
- Node execution observability via log events

**Migration Effort:** Low to Medium
- Simple search-and-replace for `skip_base_prompt` → `coding_agent`
- Update transformers to use NodeContext API (`|result|` → `|ctx|`)
- Most workflows will gain functionality without changes
- Breaking changes enable powerful new patterns

**Commit:** a7ab213 "Add node-based workflows with NodeContext and auto-delegation"

**See Also:**
- [NODE_WORKFLOWS.md](../../NODE_WORKFLOWS.md) - Complete guide with examples
- [Migration Guide](#-breaking-changes) - Detailed migration instructions above
- `examples/node_context_demo.rb` - Working demonstration

---

