# Changelog

All notable changes to SwarmCLI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.3] - 2025-10-26

### Added
- **`/defrag` Slash Command** - Automated memory defragmentation workflow
  - Discovers semantically related memory entries (60-85% similarity)
  - Creates bidirectional links to build knowledge graph
  - Runs `MemoryDefrag(action: "find_related")` then `MemoryDefrag(action: "link_related")`
  - Accessible via `/defrag` in interactive REPL

## [2.0.2]

### Added
- **Multi-line Input Support** - Interactive REPL now supports multi-line input
  - Press Option+Enter (or ESC then Enter) to add newlines without submitting
  - Press Enter to submit your message
  - Updated help documentation with input tips
- **Request Cancellation** - Press Ctrl+C to cancel an ongoing LLM request
  - Cancels the current request and returns to the prompt
  - Ctrl+C at the prompt still exits the REPL (existing behavior preserved)
  - Uses Async task cancellation for clean interruption

## [2.0.1] - Fri, Oct 17 2025

### Fixed

- Fixed interactive REPL file completion dropdown not closing after typing space following a Tab completion
- Fixed navigation mode not exiting when regular keys are typed after Tab completion

## [2.0.0] - Fri, Oct 17 2025

Initial release of SwarmCLI.

See https://github.com/parruda/claude-swarm/pull/137
