# Plugin System Guide

Complete guide to SwarmSDK's plugin architecture - how it works, how to write plugins, and what's possible.

---

## Overview

The **plugin system** allows gems to extend SwarmSDK without creating tight coupling. Plugins can provide:

- Custom tools
- Persistent storage
- Configuration options
- System prompt contributions
- Lifecycle hooks (agent init, swarm start/stop, user messages)

**Key Design Principles:**
- 🔌 **Zero Coupling** - SwarmSDK has no knowledge of plugin classes
- 🤖 **Auto-Registration** - Plugins register themselves when loaded
- 🎯 **Lifecycle Hooks** - Plugins participate in agent/swarm lifecycle
- 🛠️ **Tool Provider** - Plugins create and manage their own tools
- 📦 **Storage Provider** - Plugins handle their own data persistence

---

## Architecture

```
┌─────────────────────────────────────────┐
│  SwarmSDK (Core)                         │
│  - Plugin base class                     │
│  - PluginRegistry                        │
│  - Lifecycle hooks                       │
│  - No plugin dependencies                │
└─────────────┬───────────────────────────┘
              │
              │ (auto-registers)
              │
┌─────────────▼───────────────────────────┐
│  Plugin Gem (e.g., SwarmMemory)          │
│  - Inherits from SwarmSDK::Plugin        │
│  - Implements required methods           │
│  - Registers on load                     │
│  - Provides tools & storage              │
└──────────────────────────────────────────┘
```

---

## Writing a Plugin

### Step 1: Create Plugin Class

```ruby
# lib/my_plugin/integration/sdk_plugin.rb

module MyPlugin
  module Integration
    class SDKPlugin < SwarmSDK::Plugin
      def initialize
        super
        @storages = {}  # Track per-agent storage
      end

      # Plugin identifier (must be unique)
      def name
        :my_plugin
      end

      # Tools provided by this plugin
      def tools
        [:MyTool1, :MyTool2]
      end

      # Create a tool instance
      def create_tool(tool_name, context)
        storage = context[:storage]
        agent_name = context[:agent_name]

        case tool_name
        when :MyTool1
          Tools::MyTool1.new(storage: storage, agent_name: agent_name)
        when :MyTool2
          Tools::MyTool2.new(storage: storage)
        end
      end

      # Check if storage should be created for an agent
      def storage_enabled?(agent_definition)
        agent_definition.respond_to?(:my_plugin) && agent_definition.my_plugin
      end

      # Create storage for an agent
      def create_storage(agent_name:, config:)
        directory = config.respond_to?(:directory) ? config.directory : config[:directory]

        MyPlugin::Storage.new(directory: directory)
      end

      # Contribute to system prompt
      def system_prompt_contribution(agent_definition:, storage:)
        # Load your prompt template
        File.read(File.expand_path("../prompts/my_plugin.md", __dir__))
      end

      # Tools that should be immutable (can't be removed)
      def immutable_tools
        [:MyTool1]
      end

      # Called when agent is initialized
      def on_agent_initialized(agent_name:, agent:, context:)
        storage = context[:storage]
        return unless storage

        # Store for later use
        @storages[agent_name] = storage

        # Mark tools as immutable
        agent.mark_tools_immutable(immutable_tools.map(&:to_s))
      end

      # Called on every user message
      def on_user_message(agent_name:, prompt:, is_first_message:)
        storage = @storages[agent_name]
        return [] unless storage

        # Perform some analysis and return system reminders
        if should_suggest_something?(prompt)
          ["<system-reminder>Helpful suggestion here</system-reminder>"]
        else
          []
        end
      end
    end
  end
end
```

### Step 2: Auto-Register Plugin

```ruby
# lib/my_plugin.rb

require 'swarm_sdk'
require_relative 'my_plugin/integration/sdk_plugin'

module MyPlugin
  # ... your gem code ...
end

# Auto-register with SwarmSDK when loaded
if defined?(SwarmSDK) && defined?(SwarmSDK::PluginRegistry)
  SwarmSDK::PluginRegistry.register(MyPlugin::Integration::SDKPlugin.new)
end
```

### Step 3: Add DSL Support (Optional)

```ruby
# Add configuration method to Agent::Builder
module SwarmSDK
  module Agent
    class Builder
      def my_plugin(&block)
        @my_plugin_config = MyPluginConfig.new
        @my_plugin_config.instance_eval(&block) if block_given?
        @my_plugin_config
      end
    end
  end
end
```

**Usage:**
```ruby
agent :assistant do
  my_plugin do
    directory ".swarm/my-plugin-data"
    option "value"
  end
end
```

---

## Plugin Interface Reference

### Required Methods

```ruby
class MyPlugin < SwarmSDK::Plugin
  # Plugin identifier (Symbol) - REQUIRED
  def name
    :my_plugin
  end
end
```

### Optional Methods

```ruby
# List of tools provided
def tools
  [:Tool1, :Tool2]
end

# Create a tool instance
# context = {agent_name:, storage:, agent_definition:, chat:, tool_configurator:}
def create_tool(tool_name, context)
  MyTool.new(...)
end

# Create plugin storage for an agent
def create_storage(agent_name:, config:)
  MyStorage.new(...)
end

# Check if storage should be created
def storage_enabled?(agent_definition)
  agent_definition.respond_to?(:my_plugin)
end

# Parse configuration from agent definition
def parse_config(raw_config)
  raw_config  # Or transform as needed
end

# Contribute to agent system prompt
def system_prompt_contribution(agent_definition:, storage:)
  "# My Plugin Guidance\n..."
end

# Tools that can't be removed
def immutable_tools
  [:MyTool1]
end

# Lifecycle: Agent initialized
def on_agent_initialized(agent_name:, agent:, context:)
  # Setup, register tools, mark immutable, etc.
end

# Lifecycle: Swarm started
def on_swarm_started(swarm:)
  # Global initialization
end

# Lifecycle: Swarm stopped
def on_swarm_stopped(swarm:)
  # Cleanup, save state, etc.
end

# Lifecycle: User message (EVERY message)
def on_user_message(agent_name:, prompt:, is_first_message:)
  # Analyze prompt, return system reminders
  []  # Array of reminder strings
end
```

---

## Lifecycle Hooks

### Hook Execution Order

```
1. Swarm created
   ↓
2. Agents initialized
   → Plugin.create_storage()
   → Plugin.on_agent_initialized()
   ↓
3. Swarm.execute() called
   → Plugin.on_swarm_started()
   ↓
4. User message
   → Plugin.on_user_message()  [Returns reminders]
   → Agent sees reminders
   → Agent responds
   ↓
5. Swarm stops
   → Plugin.on_swarm_stopped()
```

### on_agent_initialized

**Purpose:** Setup plugin-specific agent configuration

**Use cases:**
- Register additional tools (like LoadSkill that needs chat reference)
- Mark tools as immutable
- Store agent storage reference for later use
- Configure agent-specific settings

**Example:**
```ruby
def on_agent_initialized(agent_name:, agent:, context:)
  @storages[agent_name] = context[:storage]

  # Register special tool
  special_tool = create_special_tool(context)
  agent.with_tool(special_tool)

  # Mark tools as immutable
  agent.mark_tools_immutable(["MyTool1", "MyTool2"])
end
```

### on_user_message

**Purpose:** Inject context-aware system reminders

**Use cases:**
- Semantic skill discovery
- Context injection based on prompt
- Suggested actions
- Warning/guidance

**Example:**
```ruby
def on_user_message(agent_name:, prompt:, is_first_message:)
  storage = @storages[agent_name]
  return [] unless storage

  # Search for relevant knowledge
  results = storage.search(prompt, threshold: 0.65)
  return [] if results.empty?

  # Return system reminder
  ["<system-reminder>Found #{results.size} relevant entries...</system-reminder>"]
end
```

**Important:** Reminders are **ephemeral** - sent to LLM but not persisted in conversation.

---

## Real-World Example: SwarmMemory

See how SwarmMemory implements the plugin interface:

**File:** `lib/swarm_memory/integration/sdk_plugin.rb`

**Provides:**
- 9 tools (MemoryWrite, MemoryRead, ..., LoadSkill)
- Filesystem storage with embeddings
- Memory system prompt
- Dual semantic search (skills + memories)
- Relationship discovery

**Key Implementation Details:**

```ruby
class SDKPlugin < SwarmSDK::Plugin
  def initialize
    super
    @storages = {}  # Track storages per agent
  end

  def tools
    # LoadSkill NOT here - registered in on_agent_initialized
    [:MemoryWrite, :MemoryRead, :MemoryEdit, ...]
  end

  def create_storage(agent_name:, config:)
    directory = extract_directory(config)
    embedder = Embeddings::InformersEmbedder.new
    adapter = Adapters::FilesystemAdapter.new(directory: directory)

    Storage.new(adapter: adapter, embedder: embedder)
  end

  def on_agent_initialized(agent_name:, agent:, context:)
    # Store for later
    @storages[agent_name] = context[:storage]

    # Register LoadSkill (needs chat + tool_configurator)
    load_skill = create_load_skill_tool(context)
    agent.with_tool(load_skill)

    # Mark all memory tools immutable
    agent.mark_tools_immutable(immutable_tools)
  end

  def on_user_message(agent_name:, prompt:, is_first_message:)
    storage = @storages[agent_name]
    return [] unless storage&.semantic_index

    # Parallel search for skills AND memories
    Async do |task|
      skills = task.async { search_skills(prompt) }
      memories = task.async { search_memories(prompt) }

      # Build reminders for both
      reminders = []
      reminders << build_skill_reminder(skills.wait) if skills.wait.any?
      reminders << build_memory_reminder(memories.wait) if memories.wait.any?
      reminders
    end.wait
  end
end
```

---

## Testing Plugins

### Unit Tests

```ruby
class MyPluginTest < Minitest::Test
  def test_plugin_registration
    assert SwarmSDK::PluginRegistry.registered?(:my_plugin)

    plugin = SwarmSDK::PluginRegistry.get(:my_plugin)
    assert_instance_of MyPlugin::Integration::SDKPlugin, plugin
  end

  def test_plugin_provides_tools
    plugin = SwarmSDK::PluginRegistry.get(:my_plugin)

    assert_includes plugin.tools, :MyTool1
    assert_includes plugin.tools, :MyTool2
  end

  def test_tool_creation
    plugin = SwarmSDK::PluginRegistry.get(:my_plugin)
    storage = MyPlugin::Storage.new(directory: "/tmp/test")

    context = { agent_name: :test, storage: storage }
    tool = plugin.create_tool(:MyTool1, context)

    assert_instance_of MyPlugin::Tools::MyTool1, tool
  end
end
```

### Integration Tests

```ruby
def test_plugin_tools_available_to_agent
  swarm = SwarmSDK.build do
    agent :test do
      my_plugin { directory "/tmp/test" }
    end
  end

  agent = swarm.agent(:test)

  # Plugin tools should be registered
  assert agent.tools.key?(:MyTool1)
  assert agent.tools.key?(:MyTool2)
end
```

---

## Plugin Registry API

### Registration

```ruby
# Auto-registration (recommended)
SwarmSDK::PluginRegistry.register(MyPlugin.new)

# Check registration
SwarmSDK::PluginRegistry.registered?(:my_plugin)  # => true
```

### Lookup

```ruby
# Get plugin by name
plugin = SwarmSDK::PluginRegistry.get(:my_plugin)

# Check if tool is provided by plugin
SwarmSDK::PluginRegistry.plugin_tool?(:MyTool1)  # => true

# Get plugin for a tool
plugin = SwarmSDK::PluginRegistry.plugin_for_tool(:MyTool1)
plugin.name  # => :my_plugin
```

### All Plugins

```ruby
# Get all registered plugins
plugins = SwarmSDK::PluginRegistry.all  # => [plugin1, plugin2]

# Get all plugin tools
tools = SwarmSDK::PluginRegistry.tools  # => {MyTool1: plugin1, MyTool2: plugin1}
```

---

## Best Practices

### 1. Single Responsibility

Each plugin should have a **focused purpose**:

✅ **Good:** Memory storage plugin, Database plugin, Analytics plugin
❌ **Bad:** "Utilities" plugin with unrelated tools

### 2. Minimal Dependencies

Plugins should have **minimal external dependencies**:

```ruby
# Check if dependency available
def create_storage(...)
  unless defined?(SomeDependency)
    raise PluginError, "my_plugin requires 'some_gem'. Install: gem install some_gem"
  end

  SomeDependency.new(...)
end
```

### 3. Graceful Degradation

Plugins should **degrade gracefully** if features unavailable:

```ruby
def on_user_message(agent_name:, prompt:, is_first_message:)
  storage = @storages[agent_name]

  # No storage? Return empty (no crash)
  return [] unless storage

  # Feature unavailable? Silent degradation
  return [] unless storage.respond_to?(:search)

  # Feature available - use it
  results = storage.search(prompt)
  results.any? ? [build_reminder(results)] : []
end
```

### 4. Namespace Your Tools

Use descriptive, namespaced tool names:

✅ **Good:** `MemoryWrite`, `DatabaseQuery`, `AnalyticsTrack`
❌ **Bad:** `Write`, `Query`, `Track` (conflicts with built-ins)

### 5. Document Everything

Plugins should have:
- Comprehensive README
- Tool descriptions (in tool classes)
- Configuration examples
- Troubleshooting guide

---

## Advanced Patterns

### Conditional Tool Registration

Register different tools based on configuration:

```ruby
def on_agent_initialized(agent_name:, agent:, context:)
  config = context[:agent_definition].my_plugin

  # Conditionally register tools
  if config.experimental_features
    experimental_tool = create_experimental_tool(context)
    agent.with_tool(experimental_tool)
  end
end
```

### Tool Swapping

Dynamically change available tools:

```ruby
def on_user_message(agent_name:, prompt:, is_first_message:)
  # Detect if user wants specialized mode
  if prompt.include?("debug mode")
    # Agent can swap tools based on this hint
    ["<system-reminder>Debug mode detected. Load debug skill for specialized tools.</system-reminder>"]
  else
    []
  end
end
```

### Multi-Agent Coordination

Plugins can coordinate across agents:

```ruby
class CoordinationPlugin < SwarmSDK::Plugin
  def initialize
    super
    @shared_state = {}
  end

  def on_agent_initialized(agent_name:, agent:, context:)
    @shared_state[agent_name] = { initialized_at: Time.now }
  end

  def on_user_message(agent_name:, prompt:, is_first_message:)
    # Check what other agents are doing
    other_agents = @shared_state.keys - [agent_name]

    if other_agents.any?
      ["<system-reminder>Other active agents: #{other_agents.join(", ")}</system-reminder>"]
    else
      []
    end
  end
end
```

---

## Plugin Development Checklist

### Before Publishing

- [ ] Plugin class inherits from `SwarmSDK::Plugin`
- [ ] `name` method returns unique symbol
- [ ] Auto-registration code in main gem file
- [ ] All tools have comprehensive descriptions
- [ ] Storage adapter (if any) handles errors gracefully
- [ ] Lifecycle hooks implemented as needed
- [ ] Unit tests for plugin class
- [ ] Integration tests with SwarmSDK
- [ ] README with installation and usage
- [ ] Example swarm configuration
- [ ] Troubleshooting section

### Quality Checklist

- [ ] Plugin works when SwarmSDK is standalone (no crashes)
- [ ] Graceful error messages if dependencies missing
- [ ] No global state pollution
- [ ] Thread-safe (if using shared state)
- [ ] Fiber-safe (if using Async operations)
- [ ] Tools have `name` method returning simple strings
- [ ] Configuration validated with helpful errors
- [ ] Works with both Ruby DSL and YAML

---

## Common Pitfalls

### ❌ Pitfall 1: Circular Dependencies

```ruby
# BAD - SwarmSDK would depend on MyPlugin
require 'swarm_sdk'
require 'my_plugin'  # SwarmSDK has: require 'my_plugin'

# GOOD - No circular dependency
require 'swarm_sdk'  # No my_plugin references
require 'my_plugin'  # Requires swarm_sdk, registers plugin
```

### ❌ Pitfall 2: Hardcoding in SDK

```ruby
# BAD - SDK knows about plugin
if defined?(MyPlugin)
  do_something_with_my_plugin
end

# GOOD - SDK uses plugin interface
SwarmSDK::PluginRegistry.all.each do |plugin|
  plugin.on_agent_initialized(...)
end
```

### ❌ Pitfall 3: Not Handling Missing Storage

```ruby
# BAD - Crashes if storage nil
def on_user_message(agent_name:, prompt:, is_first_message:)
  storage = @storages[agent_name]
  results = storage.search(prompt)  # BOOM if storage is nil
end

# GOOD - Graceful handling
def on_user_message(agent_name:, prompt:, is_first_message:)
  storage = @storages[agent_name]
  return [] unless storage  # Early return

  results = storage.search(prompt)
  # ...
end
```

### ❌ Pitfall 4: Forgetting to Track Storage

```ruby
# BAD - Storage created but not tracked
def create_storage(...)
  MyStorage.new(...)
  # Forgot to store it!
end

# In on_user_message:
storage = @storages[agent_name]  # nil!

# GOOD - Track in on_agent_initialized
def on_agent_initialized(agent_name:, agent:, context:)
  @storages[agent_name] = context[:storage]
end
```

---

## Examples

### Minimal Plugin

```ruby
class MinimalPlugin < SwarmSDK::Plugin
  def name
    :minimal
  end

  def tools
    [:Echo]
  end

  def create_tool(tool_name, context)
    Tools::Echo.new
  end
end

SwarmSDK::PluginRegistry.register(MinimalPlugin.new)
```

### Storage Plugin

```ruby
class StoragePlugin < SwarmSDK::Plugin
  def initialize
    super
    @databases = {}
  end

  def name
    :database
  end

  def storage_enabled?(agent_definition)
    agent_definition.respond_to?(:database)
  end

  def create_storage(agent_name:, config:)
    Database.connect(config.url)
  end

  def on_agent_initialized(agent_name:, agent:, context:)
    @databases[agent_name] = context[:storage]
  end

  def tools
    [:DbQuery, :DbInsert]
  end

  def create_tool(tool_name, context)
    db = context[:storage]

    case tool_name
    when :DbQuery
      Tools::DbQuery.new(db: db)
    when :DbInsert
      Tools::DbInsert.new(db: db)
    end
  end
end
```

### Analytics Plugin

```ruby
class AnalyticsPlugin < SwarmSDK::Plugin
  def name
    :analytics
  end

  def on_user_message(agent_name:, prompt:, is_first_message:)
    # Track every user message
    Analytics.track(
      event: "user_message",
      agent: agent_name,
      prompt_length: prompt.length,
      is_first: is_first_message
    )

    []  # No reminders
  end

  def on_swarm_stopped(swarm:)
    # Flush analytics on shutdown
    Analytics.flush
  end
end
```

---

## See Also

- **SwarmMemory Plugin:** `lib/swarm_memory/integration/sdk_plugin.rb` - Real-world example
- **Plugin Base Class:** `lib/swarm_sdk/plugin.rb` - Interface definition
- **PluginRegistry:** `lib/swarm_sdk/plugin_registry.rb` - Registry implementation
- **Writing Adapters:** `docs/v2/guides/memory-adapters.md` - Storage adapters
