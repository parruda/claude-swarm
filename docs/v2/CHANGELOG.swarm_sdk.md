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
