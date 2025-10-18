# Changelog

All notable changes to SwarmSDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
