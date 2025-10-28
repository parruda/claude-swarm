# Changelog

All notable changes to SwarmSDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.1]

### Added
- **OpenAI proxy compatibility**: New `openai_use_system_role` configuration
  - Automatically enabled for OpenAI-compatible providers (OpenAI, DeepSeek, Perplexity, Mistral, OpenRouter)
  - Uses standard 'system' role instead of OpenAI's newer 'developer' role
  - Improves compatibility with proxy services that don't support 'developer' role
  - Configured automatically based on provider type

### Changed
- **Think tool parameter handling**: Simplified to accept flexible parameters
  - Changed signature from `execute(thoughts:)` to `execute(**kwargs)`
  - Removes strict validation errors for parameter mismatches
  - More flexible for LLM tool calling variations
  - Added reminder in description: "The Think tool takes only one parameter: thoughts"

### Fixed
- **Nil response error handling**: Better error messages for malformed API responses
  - Detects when provider returns nil response (unparseable API response)
  - Provides detailed error message with provider info, API base, model ID
  - Suggests enabling RubyLLM debug logging to inspect raw API response
  - Prevents cryptic errors when API returns malformed/unparseable responses

## [2.1.0] - 2025-10-27

### Added
- **Think tool for explicit reasoning**: New built-in tool that enables agents to "think out loud"
  - Parameter: `thoughts` - records agent's thinking process as function calls
  - Creates "attention sinks" in conversation history for better reasoning
  - Based on chain-of-thought prompting research
  - Included as a default tool for all agents
  - Usage: `Think(thoughts: "Let me break this down: 1) Read file, 2) Analyze, 3) Implement")`

- **disable_default_tools configuration**: Flexible control over which default tools are included
  - Accepts `true` to disable ALL default tools
  - Accepts array to disable specific tools: `[:Think, :TodoWrite]`
  - Works in both Ruby DSL and YAML configurations
  - Example: `disable_default_tools [:Think, :Grep]` keeps other defaults

### Fixed
- **Model alias resolution**: Fixed bug where model aliases weren't resolved before being passed to RubyLLM
  - Aliases like `sonnet`, `opus`, `haiku` now properly resolve to full model IDs
  - `sonnet` → `claude-sonnet-4-5-20250929`
  - Works with both Ruby DSL and markdown agent files
  - Prevents "model does not exist" API errors when using aliases

### Changed
- **BREAKING CHANGE: Removed include_default_tools**: Replaced with `disable_default_tools`
  - Migration: `include_default_tools: false` → `disable_default_tools: true`
  - More intuitive API (disable what you don't want vs enable what you do)
  - Updated all documentation and examples

## [2.0.8] - 2025-10-27
- Bump RubyLLM MCP gem and remove monkey patch

## [2.0.7] - 2025-10-26

### Added

- **Plugin System** - Extensible architecture for decoupling core SDK from extensions
  - `SwarmSDK::Plugin` base class with lifecycle hooks
  - `SwarmSDK::PluginRegistry` for plugin management
  - Plugins provide tools, storage, configuration, and system prompt contributions
  - Lifecycle hooks: `on_agent_initialized`, `on_swarm_started`, `on_swarm_stopped`, `on_user_message`
  - Zero coupling: SwarmSDK has no knowledge of SwarmMemory classes
  - Auto-registration: Plugins register themselves when loaded
  - See new guide: `docs/v2/guides/plugins.md`

- **ContextManager** - Intelligent conversation context optimization
  - **Ephemeral System Reminders**: Sent to LLM but not persisted (90% token savings)
  - **Automatic Compression**: Triggers at 60% context usage
  - **Progressive Compression**: Older tool results compressed more aggressively
  - **Smart Re-run Instructions**: Idempotent tools (Read, Grep, Glob) get re-run hints
  - Token savings: 13,800-63,800 tokens per long conversation
  - See documentation: `docs/v2/reference/ruby-dsl.md#context-management`

- **Agent Name Tracking** - `Agent::Chat` now tracks `@agent_name`
  - Enables plugin callbacks per agent
  - Used for semantic skill discovery
  - Passed to lifecycle hooks

- **Parameter Validation** - Validates required parameters before tool execution
  - Checks all required parameters are present
  - Provides detailed error messages with parameter descriptions
  - Prevents "missing keyword" errors from reaching tools
  - Replaces Ruby's "keyword" terminology with user-friendly "parameter"

### Changed

- **Tool Registration** - Moved from hardcoded to plugin-based
  - Memory tools no longer hardcoded in ToolConfigurator
  - Plugins provide their own tools via `plugin.tools` and `plugin.create_tool()`
  - `MEMORY_TOOLS` constant removed (now in plugin)
  - ToolConfigurator uses `PluginRegistry.plugin_tool?()` for lookups

- **Storage Management** - Generalized for plugins
  - `@memory_storages` → `@plugin_storages` (supports any plugin)
  - Format: `{ plugin_name => { agent_name => storage } }`
  - Plugins create their own storage via `plugin.create_storage()`

- **System Prompt Contributions** - Plugin-based
  - `Agent::Definition` collects contributions from all plugins
  - Plugins contribute via `plugin.system_prompt_contribution()`
  - No hardcoded memory prompt rendering in SDK

- **Context Warning Thresholds** - Expanded
  - **Was**: [80, 90]
  - **Now**: [60, 80, 90]
  - 60% triggers automatic compression
  - 80%/90% remain as informational warnings

### Removed

- **Tools::Registry Extension System** - Replaced by plugin system
  - `register_extension()` method removed
  - Extensions no longer checked in `get()`, `exists()`, `available_names()`
  - Use `PluginRegistry` instead for extension tools

### Breaking Changes

⚠️ **Major breaking changes:**

1. **No backward compatibility with old memory integration**
   - Old `Tools::Registry.register_extension()` removed
   - Memory tools MUST use plugin system
   - SwarmMemory updated to use plugin (no migration needed if using latest)

2. **Tool creation signature changed**
   - `create_tool_instance()` now accepts `chat:` and `agent_definition:` parameters
   - Needed for plugin tools that require full context

3. **AgentInitializer signature changed**
   - Constructor now takes `plugin_storages` instead of `memory_storages`
   - Internal change - doesn't affect public API

## [2.0.6]

### Fixed
- **MCP parameter type handling**: Fixed issue with parameter type conversion in ruby_llm-mcp
  - Added monkey patch to remove `to_sym` conversion on MCP parameter types

## [2.0.5]

### Added

- **WebFetch Tool** - Fetch and process web content
  - Fetches URLs and converts HTML to Markdown
  - Optional LLM processing via `SwarmSDK.configure { |c| c.webfetch_provider; c.webfetch_model }`
  - Uses `reverse_markdown` gem if installed, falls back to built-in converter
  - 15-minute caching, redirect detection, comprehensive error handling
  - Default tool (available to all agents)

- **HtmlConverter** - HTML to Markdown conversion
  - Conditional gem usage pattern (uses `reverse_markdown` if installed)
  - Built-in fallback for common HTML elements
  - Follows DocumentConverter pattern for consistency

- **Memory System** - Per-agent persistent knowledge storage
  - **MemoryStorage class**: Persistent storage to `{directory}/memory.json`
  - **7 Memory tools**: MemoryWrite, MemoryRead, MemoryEdit, MemoryMultiEdit, MemoryGlob, MemoryGrep, MemoryDelete
  - Per-agent isolation (each agent has own memory)
  - Search results ordered by most recent first
  - Configured via `memory { directory }` DSL or `memory:` YAML field
  - Auto-injected memory system prompt from `lib/swarm_sdk/prompts/memory.md.erb`
  - Comprehensive learning protocols and schemas included

- **Memory Configuration DSL**
  ```ruby
  agent :assistant do
    memory do
      adapter :filesystem  # optional, default
      directory ".swarm/assistant-memory"  # required
    end
  end
  ```

- **Memory Configuration YAML**
  ```yaml
  agents:
    assistant:
      memory:
        adapter: filesystem
        directory: .swarm/assistant-memory
  ```

- **Scratchpad Configuration DSL** - Enable/disable at swarm level
  ```ruby
  SwarmSDK.build do
    use_scratchpad true  # or false (default: true)
  end
  ```

- **Scratchpad Configuration YAML**
  ```yaml
  swarm:
    use_scratchpad: true  # or false
  ```

- **Agent Start Events** - New log event after agent initialization
  - Emits `agent_start` with full agent configuration
  - Includes: agent, model, provider, directory, system_prompt, tools, delegates_to, memory_enabled, memory_directory, timestamp
  - Useful for debugging and configuration verification

- **SwarmSDK Global Settings** - `SwarmSDK.configure` for global configuration
  - WebFetch settings: `webfetch_provider`, `webfetch_model`, `webfetch_base_url`, `webfetch_max_tokens`
  - Separate from YAML Configuration class (renamed to Settings internally)

- **Learning Assistant Example** - Complete example in `examples/learning-assistant/`
  - Agent that learns and builds knowledge over time
  - Memory schema with YAML frontmatter + Markdown
  - Example memory entries (concept, fact, skill, experience)
  - Comprehensive learning protocols and best practices

### Changed

- **Scratchpad Architecture** - Complete redesign
  - **Was**: Single persistent storage with comprehensive tools (Edit, Glob, Grep, etc.)
  - **Now**: Simplified volatile storage with 3 tools (Write, Read, List)
  - **Purpose**: Temporary work-in-progress sharing between agents
  - **Scope**: Shared across all agents (volatile, in-memory only)
  - **Old comprehensive features** moved to Memory system

- **Storage renamed**: `updated_at` instead of `created_at`
  - More accurate since writes update existing entries
  - Affects both MemoryStorage and ScratchpadStorage

- **Storage architecture** - Introduced abstract base class
  - `Storage` (abstract base)
  - `MemoryStorage` (persistent, per-agent)
  - `ScratchpadStorage` (volatile, shared)
  - Future-ready for SQLite and FAISS adapters

- **Default tools** - Conditional inclusion
  - Core defaults: Read, Grep, Glob, TodoWrite, Think, WebFetch
  - Scratchpad tools: Added if `use_scratchpad true` (default)
  - Memory tools: Added if agent has `memory` configured
  - Enables fine-grained control over tool availability

- **Cost Tracking** - Fixed to use SwarmSDK's models.json
  - **Was**: Used `RubyLLM.models.find()` which lacks current model pricing
  - **Now**: Uses `SwarmSDK::Models.find()` with up-to-date pricing
  - Accurate cost calculation for all models in SwarmSDK registry

- **Read tracker renamed**: `ScratchpadReadTracker` → `StorageReadTracker`
  - More general name since it's used by both Memory and Scratchpad
  - Consistent with Storage abstraction

### Removed

- **Old Scratchpad tools** - Moved to Memory system
  - ScratchpadEdit → MemoryEdit
  - ScratchpadMultiEdit → MemoryMultiEdit
  - ScratchpadGlob → MemoryGlob
  - ScratchpadGrep → MemoryGrep
  - ScratchpadDelete → MemoryDelete

- **Scratchpad persistence** - Now volatile
  - No longer persists to `.swarm/scratchpad.json`
  - Use Memory system for persistent storage

### Breaking Changes

⚠️ **Major breaking changes requiring migration:**

1. **Scratchpad tools removed**: ScratchpadEdit, ScratchpadMultiEdit, ScratchpadGlob, ScratchpadGrep, ScratchpadDelete
   - **Migration**: Use Memory tools instead for persistent storage needs

2. **Scratchpad is now volatile**: Does not persist across sessions
   - **Migration**: Configure `memory` for agents that need persistence

3. **Storage field renamed**: `created_at` → `updated_at`
   - **Migration**: Old persisted scratchpad.json files will not load

4. **Default tools behavior changed**: Memory and Scratchpad are conditional
   - Scratchpad: Enabled by default via `use_scratchpad true`
   - Memory: Opt-in via `memory` configuration
   - **Migration**: Explicitly configure if needed

## [2.0.4]

### Added
- **ScratchpadGlob Tool** - Search scratchpad entries by glob pattern
  - Supports `*` (wildcard), `**` (recursive), and `?` (single char) patterns
  - Returns matching entries with titles and sizes
  - Example: `ScratchpadGlob.execute(pattern: "parallel/*/task_*")`
- **ScratchpadGrep Tool** - Search scratchpad content by regex pattern
  - Case-sensitive and case-insensitive search options
  - Three output modes: `files_with_matches`, `content` (with line numbers), `count`
  - Example: `ScratchpadGrep.execute(pattern: "error", output_mode: "content")`
- **ScratchpadRead Line Numbers** - Now returns formatted output with line numbers
  - Uses same format as Read tool: `"line_number→content"`
  - Compatible with Edit/MultiEdit tools for accurate content matching
- **ScratchpadEdit Tool** - Edit scratchpad entries with exact string replacement
  - Performs exact string replacements in scratchpad content
  - Enforces read-before-edit rule for safety
  - Supports `replace_all` parameter for multiple replacements
  - Preserves entry titles when updating content
  - Example: `ScratchpadEdit.execute(file_path: "report", old_string: "draft", new_string: "final")`
- **ScratchpadMultiEdit Tool** - Apply multiple edits to a scratchpad entry
  - Sequential edit application (later edits see results of earlier ones)
  - JSON-based edit specification for multiple operations
  - All-or-nothing approach: if any edit fails, no changes are saved
  - Example: `ScratchpadMultiEdit.execute(file_path: "doc", edits_json: '[{"old_string":"foo","new_string":"bar"}]')`
- **Scratchpad Persistence** - Automatic JSON file persistence
  - All scratchpad data automatically persists to `.swarm/scratchpad.json`
  - Thread-safe write operations with atomic file updates
  - Automatic loading on initialization
  - Graceful error handling for corrupted files
  - Human-readable JSON format with metadata (title, created_at, size)

### Changed
- **Scratchpad Data Location** - Moved from memory-only to persistent storage
  - Data survives swarm restarts
  - Stored in `.swarm/scratchpad.json` (hidden directory)
  - Added to `.gitignore` to prevent committing scratchpad data
- **Test Infrastructure** - Dependency injection for test isolation
  - Tests use temporary files instead of `.swarm/scratchpad.json`
  - New helper: `create_test_scratchpad()` for isolated test data
  - Automatic cleanup of test files after test runs

### Removed
- **ScratchpadList Tool** - Replaced by more powerful ScratchpadGlob
  - Use `ScratchpadGlob.execute(pattern: "**")` to list all entries
  - Use `ScratchpadGlob.execute(pattern: "prefix/**")` to filter by prefix

## [2.0.2] - 2025-10-17

### Added
- **Claude Code Agent File Compatibility** (#141)
  - Automatically detects and converts Claude Code agent markdown files
  - Supports model shortcuts: `sonnet`, `opus`, `haiku` → latest model IDs
  - DSL/YAML overrides: `agent :name, File.read("file.md") do ... end`
  - Model alias system via `model_aliases.json` for easy updates
  - Static model validation using `models.json` (no network calls, no API keys)
  - Improved model suggestions with provider prefix stripping

### Changed
- Model validation now uses SwarmSDK's static registry instead of RubyLLM's dynamic registry
- All agents now use `assume_model_exists: true` by default (SwarmSDK validates separately)
- Model suggestions properly handle provider-prefixed queries (e.g., `anthropic:claude-sonnet-4-5`)
- Environment block (`<env>`) now included in ALL agent system prompts (previously only `coding_agent: true`)

## [2.0.1] - 2025-10-17

### Fixed
- Add id to MCP notifications/initialized message (#140)

### Removed
- Removed outdated example files (examples/v2/README-formats.md and examples/v2/mcp.json)

## [2.0.0] - 2025-10-17

Initial release of SwarmSDK.

See https://github.com/parruda/claude-swarm/pull/137
