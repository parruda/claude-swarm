# Node-Based Workflows

SwarmSDK now supports **node-based workflows** - a powerful way to compose multiple swarm executions into sequential or parallel stages.

## Overview

**Nodes** enable multi-stage workflows where different teams of agents collaborate in sequence. Each node:
- Represents a mini-swarm execution stage
- Has its own delegation topology
- Executes independently with isolated state
- Passes output to dependent nodes

## Key Concepts

### Traditional Swarm (Single Execution)
```ruby
swarm = SwarmSDK.build do
  name "Simple Swarm"
  lead :backend

  agent(:backend) do
    model "gpt-4"
    delegates_to :tester
  end

  agent(:tester) do
    model "gpt-4"
  end
end

swarm.execute("Build feature")  # Single swarm execution
```

### Node-Based Workflow (Sequential Executions)
```ruby
swarm = SwarmSDK.build do
  name "Development Workflow"

  # Define agents globally
  agent(:planner) { ... }
  agent(:backend) { ... }
  agent(:tester) { ... }

  # Stage 1: Planning
  node :planning do
    agent(:planner)  # Solo agent
  end

  # Stage 2: Implementation
  node :implementation do
    agent(:backend).delegates_to(:tester)  # Team collaboration
    agent(:tester)
    depends_on :planning  # Runs after planning completes
  end

  start_node :planning  # Entry point
end

swarm.execute("Build feature")  # Executes planning → implementation
```

## Node DSL Reference

### Defining Nodes

```ruby
node :node_name do
  # Node configuration
end
```

### Configuring Agents in Nodes

```ruby
node :implementation do
  # Solo agent (no delegation)
  agent(:planner)

  # Agent with delegation
  agent(:backend).delegates_to(:tester, :database)
  # tester and database are auto-added - no need to declare them!

  # Multiple agents forming a chain
  agent(:backend).delegates_to(:tester)
  agent(:tester).delegates_to(:database)
  # database is auto-added automatically
end
```

**Auto-add Behavior:**

Agents mentioned in `delegates_to` are **automatically added** to the node with no delegation of their own. You only need to explicitly declare an agent if it has its own delegation:

```ruby
node :complex do
  # Only declare agents with delegation
  agent(:lead).delegates_to(:backend, :frontend)
  agent(:backend).delegates_to(:database)

  # These are auto-added (no declaration needed):
  # - frontend (mentioned in lead's delegates_to)
  # - database (mentioned in backend's delegates_to)
end
```

**When to explicitly declare:**

```ruby
node :impl do
  agent(:backend).delegates_to(:tester)
  agent(:tester).delegates_to(:database) # Explicit: tester has delegation
  # database auto-added (no delegation)
end
```

### Setting Lead Agent

By default, the **first agent declared** in a node becomes the lead (entry point):

```ruby
node :work do
  agent(:backend).delegates_to(:tester)  # backend is lead
  agent(:tester)
end
```

You can explicitly override the lead:

```ruby
node :work do
  agent(:backend).delegates_to(:tester)
  agent(:tester)
  lead :tester  # tester is lead instead of backend
end
```

### Declaring Dependencies

```ruby
node :implementation do
  # ...
  depends_on :planning  # Runs after planning node completes
end

node :deployment do
  # ...
  depends_on :testing, :integration  # Runs after both complete
end
```

### Setting Start Node

```ruby
start_node :planning  # Required when using nodes
```

### Input/Output Transformers with NodeContext

Transform data flowing between nodes. Transformers can be:
- **Ruby blocks** (DSL only) - Full Ruby power with NodeContext
- **Bash commands** (DSL + YAML) - External scripts with JSON I/O

**Transformers receive a NodeContext object** with rich access to workflow state.

**Importantly, transformers run at execution time, not declaration time**, so you can use them for side effects like logging, file I/O, or dynamic configuration.

#### NodeContext API

**All transformers receive a NodeContext with:**

- `ctx.content` - Convenience accessor for current/previous content
- `ctx.original_prompt` - The original user prompt (available in ALL nodes!)
- `ctx.all_results` - Hash of all previous node results (`ctx.all_results[:node_name]`)
- `ctx.node_name` - Current node name
- `ctx.dependencies` - List of dependency nodes (input transformers only)
- `ctx.result` - Current node's Result object (output transformers only)
- `ctx.previous_result` - Previous node's Result object (input transformers only)

#### Basic Data Transformation

```ruby
node :planning do
  agent(:architect)

  # Output transformer receives NodeContext
  output do |ctx|
    # ctx.content = this node's result
    # ctx.original_prompt = original user prompt
    "PLAN:\n#{ctx.content}\n\nNow implement this plan."
  end
end

node :implementation do
  agent(:backend).delegates_to(:tester)
  depends_on :planning

  # Input transformer receives NodeContext
  input do |ctx|
    # ctx.content = transformed output from planning
    # ctx.original_prompt = original user prompt
    "Context: #{ctx.content}"
  end
end
```

#### Access Original Prompt from Any Node

```ruby
node :review do
  agent(:reviewer)
  depends_on :implementation

  input do |ctx|
    # Include original prompt in review context
    <<~PROMPT
      ORIGINAL REQUEST: #{ctx.original_prompt}

      IMPLEMENTATION:
      #{ctx.content}

      Does this meet the original request?
    PROMPT
  end
end
```

#### Access All Previous Node Results

```ruby
node :final_review do
  agent(:architect)
  depends_on :implementation

  input do |ctx|
    # Access specific previous nodes
    plan = ctx.all_results[:planning].content
    impl = ctx.all_results[:implementation].content
    tests = ctx.all_results[:testing].content

    <<~PROMPT
      Review complete workflow:

      ORIGINAL: #{ctx.original_prompt}
      PLAN: #{plan}
      IMPLEMENTATION: #{impl}
      TESTS: #{tests}

      Provide overall assessment.
    PROMPT
  end
end
```

#### Side Effects at Runtime

Transformers can execute arbitrary Ruby code when the node runs:

```ruby
node :planning do
  agent(:architect)

  # Input transformer runs when node starts
  input do |ctx|
    # Side effects: logging, file I/O, etc.
    puts "Starting planning at #{Time.now}"
    File.write("logs/planning_start.txt", Time.now.to_s)

    # Still need to return the transformed input
    "Context from previous step: #{ctx.content}"
  end

  # Output transformer runs when node completes
  output do |ctx|
    # Side effects: save results, send notifications
    File.write("results/plan.txt", ctx.content)
    send_slack_notification("Planning complete!")

    # Return transformed output for next node
    "PLAN:\n#{ctx.content}"
  end
end
```

#### Multiple Side Effects

You can have complex logic in transformers:

```ruby
node :implementation do
  agent(:backend).delegates_to(:tester)
  depends_on :planning

  input do |ctx|
    # Dynamic configuration at runtime
    api_keys = fetch_api_keys_from_vault
    ENV['API_KEY'] = api_keys[:backend]

    # Log what we're doing
    logger.info("Backend starting with plan: #{ctx.content[0..100]}")

    # Prepare enhanced input
    <<~PROMPT
      API Keys configured: #{api_keys.keys.join(", ")}

      Original plan:
      #{ctx.content}

      Please implement following these guidelines...
    PROMPT
  end
end
```

### Multiple Dependencies

When a node depends on multiple nodes, `ctx.previous_result` is a hash of results:

```ruby
node :integration do
  depends_on :frontend, :backend

  input do |ctx|
    # ctx.previous_result is a hash when multiple dependencies
    # ctx.content returns nil (no single content)
    # Use ctx.all_results or ctx.previous_result to access specific nodes

    frontend_output = ctx.all_results[:frontend].content
    backend_output = ctx.all_results[:backend].content

    "Integrate:\nFrontend: #{frontend_output}\nBackend: #{backend_output}"
  end
end
```

### Bash Command Transformers (YAML + DSL)

Transformers can be **external bash commands** that receive NodeContext as JSON on STDIN and output transformed content to STDOUT.

**Exit Code Behavior:**

- **Exit 0**: Transform success - Use STDOUT as transformed content
- **Exit 1**: Skip node execution - Use input unchanged, STDOUT ignored
  - Input transformer: Skips LLM execution, passes current_input through
  - Output transformer: Passes result.content through unchanged
- **Exit 2**: Halt workflow - Shows STDERR as error, STDOUT ignored

#### JSON Input Format (STDIN)

The transformer receives NodeContext as JSON:

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

#### Ruby DSL Usage

```ruby
node :implementation do
  agent(:backend)
  depends_on :planning

  # Bash command transformer
  input_command("scripts/validate_plan.sh", timeout: 30)
  output_command("scripts/format_output.sh")
end
```

#### Example: Validation (Exit 0 or Exit 2)

```bash
#!/bin/bash
# validate_plan.sh

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.content')

# Validate content length
if [ ${#CONTENT} -gt 10000 ]; then
  echo "ERROR: Plan exceeds 10K characters" >&2
  exit 2  # Halt workflow
fi

# Transform and output
echo "Validated: $CONTENT"
exit 0  # Success
```

#### Example: Caching (Exit 1 to Skip)

```bash
#!/bin/bash
# cache_check.sh

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.content')
CACHE_KEY=$(echo -n "$CONTENT" | md5)

# Check cache
if [ -f "cache/$CACHE_KEY" ]; then
  # Cache hit - skip node execution
  # STDOUT is ignored on exit 1
  exit 1  # Skip node, pass current_input through unchanged
fi

# No cache - proceed normally
echo "$CONTENT"
exit 0
```

#### Example: Access All Results

```bash
#!/bin/bash
# merge_results.sh

INPUT=$(cat)

# Extract original prompt
ORIGINAL=$(echo "$INPUT" | jq -r '.original_prompt')

# Extract planning result
PLAN=$(echo "$INPUT" | jq -r '.all_results.planning.content')

# Extract current content
CONTENT=$(echo "$INPUT" | jq -r '.content')

# Combine all context
cat <<EOF
ORIGINAL REQUEST: $ORIGINAL

PLAN: $PLAN

CURRENT: $CONTENT

Now review all of this.
EOF

exit 0
```

#### Example: Conditional Skip

```bash
#!/bin/bash
# conditional_enhance.sh

INPUT=$(cat)
CONTENT=$(echo "$INPUT" | jq -r '.content')

# Calculate quality score (simplified)
QUALITY=$(echo "$CONTENT" | wc -w)

if [ $QUALITY -gt 100 ]; then
  # High quality - skip enhancement
  exit 1  # Skip node, use input unchanged
fi

# Low quality - proceed with enhancement
echo "$CONTENT"
exit 0
```

#### Environment Variables

Transformers receive these environment variables:

- `SWARM_SDK_PROJECT_DIR` - Project root directory
- `SWARM_SDK_NODE_NAME` - Current node name
- `PATH` - System PATH

## Complete Example

```ruby
swarm = SwarmSDK.build do
  name "Software Development Workflow"

  # Define agents
  agent(:architect) do
    model "gpt-4"
    description "System architect"
    system_prompt "You design software systems"
  end

  agent(:backend_dev) do
    model "gpt-4"
    description "Backend developer"
    system_prompt "You implement APIs"
  end

  agent(:tester) do
    model "gpt-4"
    description "QA engineer"
    system_prompt "You write tests"
  end

  # Stage 1: Planning (solo architect)
  node :planning do
    agent(:architect)

    output do |ctx|
      "Architectural Plan:\n#{ctx.content}\n\nPlease implement."
    end
  end

  # Stage 2: Implementation (backend + tester collaborate)
  node :implementation do
    agent(:backend_dev).delegates_to(:tester)
    agent(:tester)

    depends_on :planning

    output do |ctx|
      "Implementation:\n#{ctx.content}\n\nPlease review."
    end
  end

  # Stage 3: Review (architect reviews)
  node :review do
    agent(:architect)
    depends_on :implementation

    input do |ctx|
      # Access original prompt and all previous results
      <<~PROMPT
        ORIGINAL REQUEST: #{ctx.original_prompt}
        PLAN: #{ctx.all_results[:planning].content}
        IMPLEMENTATION: #{ctx.content}

        Review this work.
      PROMPT
    end
  end

  start_node :planning
end

# Execute the workflow
result = swarm.execute("Build a REST API for managing todos")
```

## Agent-less Nodes (Pure Computation)

Nodes can run **pure Ruby code without any LLM execution**. These are perfect for deterministic operations between LLM stages:

```ruby
swarm = SwarmSDK.build do
  name "Data Processing Pipeline"

  agent(:analyzer) { model "gpt-4"; ... }

  # Stage 1: LLM analyzes data
  node :analyze do
    agent(:analyzer)
  end

  # Stage 2: Pure computation (no LLM)
  node :parse do
    # No agents - just transformers
    output do |ctx|
      # Extract structured data
      data = JSON.parse(ctx.content)
      {
        key_points: extract_key_points(data),
        metrics: calculate_metrics(data),
        summary: summarize(data)
      }.to_json
    end

    depends_on :analyze
  end

  # Stage 3: LLM processes parsed data
  node :report do
    agent(:analyzer)
    depends_on :parse

    input do |ctx|
      data = JSON.parse(ctx.content)
      "Create report from: #{data['summary']}"
    end
  end

  start_node :analyze
end
```

### Use Cases for Agent-less Nodes

- **Data extraction/parsing**: Extract structured data from LLM output
- **Format conversions**: Convert between formats (markdown → JSON, etc.)
- **Validation**: Check output before next stage
- **Aggregation**: Combine multiple node outputs
- **Cost optimization**: Skip expensive LLM calls for simple transformations
- **Deterministic computations**: Math, filtering, sorting, etc.

## Skip Execution (Caching & Validation)

Input transformers can **skip node execution** by returning `{ skip_execution: true, content: "..." }`. This is useful for:

### Caching

```ruby
node :expensive_analysis do
  agent(:analyzer)
  depends_on :preprocessing

  input do |ctx|
    # Check cache
    cache_key = Digest::SHA256.hexdigest(ctx.content)
    cached = CACHE[cache_key]

    if cached
      # Skip LLM call, return cached result immediately
      { skip_execution: true, content: cached }
    else
      # No cache hit - execute normally
      ctx.content
    end
  end

  output do |ctx|
    # Save to cache
    cache_key = Digest::SHA256.hexdigest(ctx.content)
    CACHE[cache_key] = ctx.content
    ctx.content
  end
end
```

### Validation (Fail Early)

```ruby
node :processor do
  agent(:processor)
  depends_on :input_stage

  input do |ctx|
    # Validate before expensive LLM call
    if ctx.content.length > 10000
      { skip_execution: true, content: "ERROR: Input exceeds 10K character limit" }
    elsif ctx.content.empty?
      { skip_execution: true, content: "ERROR: Empty input" }
    else
      ctx.content
    end
  end
end
```

### Conditional Execution

```ruby
node :optional_enhancement do
  agent(:enhancer)
  depends_on :base_processing

  input do |ctx|
    # Only enhance if quality is below threshold
    quality_score = calculate_quality(ctx.content)

    if quality_score > 0.9
      # Good enough, skip enhancement
      { skip_execution: true, content: ctx.content }
    else
      # Needs enhancement
      "Enhance this: #{ctx.content}"
    end
  end
end
```

### Rate Limiting

```ruby
node :external_api do
  agent(:api_caller)
  depends_on :preparation

  input do |ctx|
    if rate_limit_exceeded?
      # Skip and return cached/default response
      { skip_execution: true, content: get_default_response() }
    else
      ctx.content
    end
  end
end
```

## Key Features

### ✅ Full Swarm Power Within Each Node
Each node is a complete swarm execution with full delegation capabilities:

```ruby
node :complex_task do
  agent(:lead).delegates_to(:backend, :frontend, :database)
  agent(:backend).delegates_to(:api, :cache)
  agent(:frontend).delegates_to(:designer)
  # Full agent collaboration!
end
```

### ✅ Sequential Composition Between Nodes
Nodes execute in topological order based on dependencies:

```ruby
node :plan { agent(:architect) }
node :implement { agent(:backend).delegates_to(:tester); depends_on :plan }
node :deploy { agent(:devops); depends_on :implement }
start_node :plan
# Executes: plan → implement → deploy
```

### ✅ Automatic State Isolation
Each node gets fresh agent instances - no state leakage between stages.

### ✅ Flexible Data Flow
Use transformers to shape data flowing between nodes.

### ✅ Circular Dependency Detection
The orchestrator validates the node graph and prevents circular dependencies.

### ✅ Backward Compatible
Traditional single-swarm execution still works:

```ruby
# No nodes = traditional swarm
swarm = SwarmSDK.build do
  name "Simple"
  lead :backend
  agent(:backend) { ... }
end
```

## Architecture

Each node:
1. Creates an independent `Swarm` instance
2. Includes only agents specified in that node
3. Configures delegation topology per node
4. Executes with `mini_swarm.execute(input)`
5. Passes output to dependent nodes

The `NodeOrchestrator`:
- Builds execution order via topological sort
- Creates mini-swarms on demand
- Manages data flow between nodes
- Supports input/output transformers

## Node Log Events

NodeOrchestrator emits `node_start` and `node_stop` events for workflow visibility:

### node_start Event

Emitted when a node begins execution:

```ruby
{
  type: "node_start",
  node: "planning",              # Node name
  agent_less: false,             # Whether node has agents
  agents: ["architect"],         # Agents in this node
  dependencies: [],              # Nodes this depends on
  timestamp: "2025-01-15T10:30:00Z"
}
```

### node_stop Event

Emitted when a node completes:

```ruby
{
  type: "node_stop",
  node: "planning",
  agent_less: false,
  skipped: false,                # Whether execution was skipped
  agents: ["architect"],
  duration: 12.5,                # Seconds
  timestamp: "2025-01-15T10:30:12Z"
}
```

### Example Log Handling

```ruby
swarm.execute("Build feature") do |log|
  case log[:type]
  when "node_start"
    node_type = log[:agent_less] ? "Computation" : "LLM"
    puts "#{node_type} Node: #{log[:node]} starting"
  when "node_stop"
    if log[:skipped]
      puts "  ⏭️  Skipped (cached/validation)"
    elsif log[:agent_less]
      puts "  ✅ Computed in #{log[:duration]}s"
    else
      puts "  ✅ Completed in #{log[:duration]}s"
    end
  end
end
```

## Benefits

**Within Nodes:**
- Full swarm collaboration power
- Complex delegation topologies
- All existing swarm features work

**Between Nodes:**
- Sequential workflow composition
- Clear stage separation
- Flexible data transformation
- State isolation
- Execution visibility via log events

**Best of both worlds!** 🚀
