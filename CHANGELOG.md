## [Unreleased]

### Added
- **Main process PID tracking**: The orchestrator now writes its process ID to `SESSION_PATH/main_pid` for external monitoring and management
- **Swarm execution summary**: Display runtime duration and total cost at the end of each swarm run [@claudenm]
  - Shows total execution time in hours, minutes, and seconds format
  - Calculates and displays aggregate cost across all instances
  - Indicates when main instance cost is excluded (e.g., for interactive sessions)
  - Session metadata now includes end time and duration in seconds

- **Session cost calculator**: New `SessionCostCalculator` class for aggregating costs from session logs [@claudenm]
  - Processes session.log.json files to calculate total usage costs
  - Tracks which instances have cost data available

- **Session cost calculator**: New `SessionCostCalculator` class for aggregating costs from session logs
  - Processes session.log.json files to calculate total usage costs
  - Tracks which instances have cost data available

- **OpenAI provider support**: Claude Swarm now supports OpenAI models as an alternative provider
  - Instances can specify `provider: openai` in configuration (default remains "claude")
  - Full MCP tool support for OpenAI instances via automatic conversion
  - Mixed provider swarms allow Claude and OpenAI instances to collaborate
  - OpenAI instances only work with `vibe: true` at the moment. There's no way to set allowed/disallowed tools.
  
- **Dual OpenAI API support**: Two API versions available for different use cases
  - Chat Completion API (`api_version: "chat_completion"`) - Traditional format with tool calling
  - Responses API (`api_version: "responses"`) - New structured format with function calls
  - Both APIs support recursive tool execution with proper conversation tracking
  
- **OpenAI-specific configuration options**:
  - `temperature`: Control response randomness (default: 0.3)
  - `api_version`: Choose between "chat_completion" or "responses" 
  - `openai_token_env`: Custom environment variable for API key (default: "OPENAI_API_KEY")
  - `base_url`: Support for OpenAI-compatible endpoints and proxies
  
- **Enhanced debugging and logging**:
  - Detailed error response logging for OpenAI API calls
  - Conversation flow tracking with IDs for debugging
  - Full request/response logging in session JSONL files

### Changed
- Configuration validation now enforces provider-specific fields
- Example configurations moved from `example/` to `examples/` directory
- Added `mixed-provider-swarm.yml` example demonstrating Claude-OpenAI collaboration
- Session metadata now includes `start_time`, `end_time`, and `duration_seconds` fields [@claudenm]
- Updated `ps` and `show` commands to use the new cost calculation functionality [@claudenm]


### Internal
- New classes: `OpenAIExecutor`, `OpenAIChatCompletion`, `OpenAIResponses`
- Comprehensive test coverage for OpenAI provider functionality
- MCP generator enhanced to support provider-specific configurations

## [0.1.20]

### Added
- **External worktree directory**: Git worktrees are now created in `~/.claude-swarm/worktrees/` for better isolation from the main repository
  - Prevents conflicts with bundler and other tools
  - Each unique Git repository gets its own worktree with the same name
  - Session metadata tracks worktree information for restoration
- **Zeitwerk autoloading**: Implemented Zeitwerk for better code organization and loading

### Changed
- **Improved team coordination**: Removed circular dependencies in team configurations
- **Better code organization**: Refactored code structure to work with Zeitwerk autoloading

### Internal
- Updated Gemfile.lock to include zeitwerk dependency
- Added prompt best practices documentation

## [0.1.19]

### Added
- **Interactive configuration generator**: New `claude-swarm generate` command launches Claude to help create swarm configurations
  - Runs Claude in interactive mode with an initial prompt to guide configuration creation
  - Customizable output file with `-o/--output` option
  - When no output file is specified, Claude names the file based on the swarm's function (e.g., web-dev-swarm.yml, data-pipeline-swarm.yml)
  - Model selection with `-m/--model` option (default: sonnet)
  - Checks for Claude CLI installation and provides helpful error message if not found
  - Includes comprehensive initial prompt with Claude Swarm overview, best practices, and common patterns
  - Full README content is included in the prompt within `<full_readme>` tags for complete context
  - Examples: 
    - `claude-swarm generate` - Claude names file based on swarm function
    - `claude-swarm generate -o my-team.yml --model opus` - Custom file and model

### Fixed
- **ps command path display**: The `claude-swarm ps` command now shows expanded absolute paths instead of raw YAML values
  - Relative paths like `.` are expanded to their full absolute paths (e.g., `/Users/paulo/project`)
  - Multiple directories are properly expanded and displayed as comma-separated values
  - Worktree directories are correctly shown when sessions use worktrees (e.g., `/path/to/repo/.worktrees/feature-branch`)
  - Path resolution uses the start_directory from session metadata for accurate expansion

## [0.1.18]

### Added
- **Before commands**: Execute setup commands before launching the swarm
  - New `before` field in swarm configuration accepts an array of commands
  - Commands are executed in sequence before any Claude instances are launched
  - All commands must succeed (exit code 0) for the swarm to launch
  - Commands are only executed on initial launch, not when restoring sessions
  - Output is logged to the session log file
  - Useful for installing dependencies, starting services, or running setup scripts
  - Example: `before: ["npm install", "docker-compose up -d"]`

- **Git worktree support**: Run instances in isolated Git worktrees
  - New `--worktree [NAME]` CLI option creates worktrees for all instances
  - Worktrees are created inside each repository at `.worktrees/NAME`
  - Each worktree gets its own branch (not detached HEAD) for proper Git operations
  - Auto-generated names use session ID: `worktree-SESSION_ID`
  - Per-instance worktree configuration in YAML:
    - `worktree: true` - Use shared worktree name
    - `worktree: false` - Disable worktree for this instance
    - `worktree: "branch-name"` - Use custom worktree name
  - Session restoration automatically restores worktrees
  - Cleanup preserves worktrees with uncommitted changes or unpushed commits
  - Warnings displayed when worktrees are preserved: "⚠️ Warning: Worktree has uncommitted changes"
  - Multiple directories per instance work seamlessly with worktrees
  - `.gitignore` automatically created in `.worktrees/` directory
  - Example: `claude-swarm --worktree feature-branch`

## [0.1.17]

### Added
- **Multi-directory support**: Instances can now access multiple directories
  - The `directory` field in YAML configuration now accepts either a string (single directory) or an array of strings (multiple directories)
  - Additional directories are passed to Claude using the `--add-dir` flag
  - The first directory in the array serves as the primary working directory
  - All specified directories must exist or validation will fail
  - Example: `directory: [./frontend, ./backend, ./shared]`
- **Session monitoring commands**: New commands for monitoring and managing active Claude Swarm sessions
  - `claude-swarm ps`: List all active sessions with properly aligned columns showing session ID, swarm name, total cost, uptime, and directories
  - `claude-swarm show SESSION_ID`: Display detailed session information including instance hierarchy and individual costs
  - `claude-swarm watch SESSION_ID`: Tail session logs in real-time (uses native `tail -f`)
  - `claude-swarm clean`: Remove stale session symlinks with optional age filtering (`--days N`)
  - Active sessions are tracked via symlinks in `~/.claude-swarm/run/` for efficient monitoring
  - Cost tracking aggregates data from `session.log.json` for accurate reporting
  - Interactive main instance shows "n/a (interactive)" for cost when not available

## [0.1.16]

### Changed
- **Breaking change**: Removed custom permission MCP server in favor of Claude's native `mcp__MCP_NAME` pattern
- Connected instances are now automatically added to allowed tools as `mcp__<instance_name>`
- CLI parameter `--tools` renamed to `--allowed-tools` for consistency with YAML configuration
- MCP generator no longer creates permission MCP server configurations

### Removed
- Removed `PermissionMcpServer` and `PermissionTool` classes
- Removed `tools-mcp` CLI command
- Removed regex tool pattern syntax - use Claude Code patterns instead
- Removed `--permission-prompt-tool` flag from orchestrator
- Removed permission logging to `permissions.log`

### Migration Guide
- Replace custom tool patterns with Claude Code's native patterns in your YAML files:
  - `"Bash(npm:*)"` → Use `Bash` and Claude Code's built-in command restrictions
  - `"Edit(*.js)"` → Use `Edit` and Claude Code's built-in file restrictions
- For fine-grained tool control, use Claude Code's native patterns:
  - `mcp__<server_name>__<tool_name>` for specific tools from an MCP server
  - `mcp__<server_name>` to allow all tools from an MCP server
- Connected instances are automatically accessible via `mcp__<instance_name>` pattern
- See Claude Code's documentation for full details on supported tool patterns

## [0.1.15]

### Changed
- **Dependency update**: Switched from `fast-mcp` to `fast-mcp-annotations` for improved tool annotation support
- **Task tool annotations**: Added read-only, non-destructive, and closed-world hints to the task tool to allow parallel execution
- Change the task tool description to say there's no description parameter, so claude does not try to send it.

## [0.1.14]

### Changed
- **Working directory behavior**: Swarms now run from the directory where `claude-swarm` is executed, not from the directory containing the YAML configuration file
  - Instance directories in the YAML are now resolved relative to the launch directory
  - Session restoration properly restores to the original working directory
  - Fixes issues where relative paths in YAML files would resolve differently depending on config file location

## [0.1.13]

### Added
- **Session restoration support (Experimental)**: Session management with the ability to resume previous Claude Swarm sessions. Note: This is an experimental feature with limitations - the main instance's conversation context is not fully restored
  - New `--session-id` flag to resume a session by ID or path
  - New `list-sessions` command to view available sessions with metadata
  - Automatic capture and persistence of Claude session IDs for all instances
  - Individual instance states stored in `state/` directory with instance ID as filename (e.g., `state/lead_abc123.json`)
  - Swarm configuration copied to session directory as `config.yml` for restoration
- **Instance ID tracking**: Each instance now gets a unique ID in the format `instance_name_<hex>` for better identification in logs
- **Enhanced logging with instance IDs**: All log messages now include instance IDs when available (e.g., `lead (lead_1234abcd) -> backend (backend_5678efgh)`)
- **Calling instance ID propagation**: When one instance calls another, both the calling instance name and ID are passed for complete tracking
- Instance IDs are stored in MCP configuration files with `instance_id` and `instance_name` fields
- New CLI options: `--instance-id` and `--calling-instance-id` for the `mcp-serve` command
- ClaudeCodeExecutor now tracks and logs both instance and calling instance IDs
- **Process tracking and cleanup**: Added automatic tracking and cleanup of child MCP server processes
  - New `ProcessTracker` class creates individual PID files in a `pids/` directory within the session path
  - Signal handlers (INT, TERM, QUIT) ensure all child processes are terminated when the main instance exits
  - Prevents orphaned MCP server processes from continuing to run after swarm termination

### Changed
- Human-readable logs improved to show instance IDs in parentheses after instance names for easier tracking of multi-instance interactions
- `log_request` method enhanced to include instance IDs in structured JSON logs
- Configuration class now accepts optional `base_dir` parameter to support session restoration from different directories

### Fixed
- Fixed issue where child MCP server processes would continue running after the main instance exits

## [0.1.12]
### Added
- **Circular dependency detection**: Configuration validation now detects and reports circular dependencies between instances
- Clear error messages showing the dependency cycle (e.g., "Circular dependency detected: lead -> backend -> lead")
- Comprehensive test coverage for various circular dependency scenarios
- **Session management improvements**: Session files are now stored in `~/.claude-swarm/sessions/` organized by project path
- Added `SessionPath` module to centralize session path management
- Sessions are now organized by project directory for better multi-project support
- Added `CLAUDE_SWARM_HOME` environment variable support for custom storage location
- Log full JSON to `session.log.json` as JSONL

### Changed
- Session files moved from `./.claude-swarm/sessions/` to `~/.claude-swarm/sessions/[project]/[timestamp]/`
- Replaced `CLAUDE_SWARM_SESSION_TIMESTAMP` with `CLAUDE_SWARM_SESSION_PATH` environment variable
- MCP server configurations now use the new centralized session path

### Fixed
- Fixed circular dependency example in README documentation

## [0.1.11]
### Added
- Main instance debug mode with `claude-swarm --debug`

## [0.1.10]

### Added
- **YAML validation for tool fields**: Added strict validation to ensure `tools:`, `allowed_tools:`, and `disallowed_tools:` fields must be arrays in the configuration
- Clear error messages when tool fields are not arrays (e.g., "Instance 'lead' field 'tools' must be an array, got String")
- Comprehensive test coverage for the new validation rules

### Fixed
- Prevents silent conversion of non-array tool values that could lead to unexpected behavior
- Configuration now fails fast with helpful error messages instead of accepting invalid formats

## [0.1.9]

### Added
- **Parameter-based tool patterns**: Custom tools now support explicit parameter patterns (e.g., `WebFetch(url:https://example.com/*)`)
- **Enhanced pattern matching**: File tools support brace expansion and complex glob patterns (e.g., `Read(~/docs/**/*.{txt,md})`)
- **Comprehensive test coverage**: Added extensive unit and integration tests for permission system

### Changed
- **Breaking change**: Custom tools with patterns now require explicit parameter syntax - `Tool(param:pattern)` instead of `Tool(pattern)`
- **Improved pattern parsing**: Tool patterns are now parsed into structured hashes with `tool_name`, `pattern`, and `type` fields
- **Better pattern enforcement**: Custom tool patterns are now strictly enforced - requests with non-matching parameters are denied
- Tools without patterns (e.g., `WebFetch`) continue to accept any input parameters

### Fixed
- Fixed brace expansion in file glob patterns by adding `File::FNM_EXTGLOB` flag
- Improved parameter pattern parsing to avoid conflicts with URL patterns containing colons

### Internal
- Major refactoring of `PermissionMcpServer` and `PermissionTool` for better maintainability and readability
- Extracted pattern matching logic into focused, single-purpose methods
- Added constants for tool categories and pattern types
- Improved logging with structured helper methods

## [0.1.8]

### Added
- **Disallowed tools support**: New `disallowed_tools` YAML key for explicitly denying specific tools (takes precedence over allowed tools)

### Changed
- **Renamed YAML key**: `tools` renamed to `allowed_tools` while maintaining backward compatibility
- Tool permissions now support both allow and deny patterns, with deny taking precedence
- Both `--allowedTools` and `--disallowedTools` are passed as comma-separated lists to Claude
- New CLI option `--stream-logs` - can only be used with `-p`

## [0.1.7]

### Added
- **Vibe mode support**: Per-instance `vibe: true` configuration to skip all permission checks for specific instances
- **Automatic permission management**: Built-in permission MCP server that handles tool authorization without manual approval
- **Permission logging**: All permission checks are logged to `.claude-swarm/sessions/{timestamp}/permissions.log`
- **Mixed permission modes**: Support for running some instances with full permissions while others remain restricted
- **New CLI command**: `claude-swarm tools-mcp` for starting a standalone permission management MCP server
- **Permission tool patterns**: Support for wildcard patterns in tool permissions (e.g., `mcp__frontend__*`)

### Changed
- Fixed `--system-prompt` to use `--append-system-prompt` for proper Claude Code integration
- Added `--permission-prompt-tool` flag pointing to `mcp__permissions__check_permission` when not in vibe mode
- Enhanced MCP generation to include a permission server for each instance (unless in vibe mode)

### Technical Details
- Permission checks use Fast MCP server with pattern matching for tool names
- Each instance can have its own permission configuration independent of global settings
- Permission decisions are made based on configured tool patterns with wildcard support

## [0.1.6]
- Refactor: move tools out of the ClaudeMcpServer class
- Move logging into code executor and save instance interaction streams to session.log
- Human readable logs with thoughts and tool calls

## [0.1.5]

### Changed
- **Improved command execution**: Switched from `exec` to `Dir.chdir` + `system` for better process handling and proper directory context
- Command arguments are now passed as an array instead of a shell string, eliminating the need for manual shell escaping
- Added default prompt behavior: when no `-p` flag is provided, a default prompt is added to help Claude understand it should start working

### Internal
- Updated test suite to match new command execution implementation
- Removed shellwords escaping tests as they're no longer needed with array-based command execution

## [0.1.4]

### Added
- **Required `description` field for instances**: Each instance must now have a description that clearly explains its role and specialization
- Dynamic task tool descriptions that include both the instance name and description (e.g., "Execute a task using Agent frontend_dev. Frontend developer specializing in React and modern web technologies")
- Description validation during configuration parsing - configurations without descriptions will fail with a clear error message

### Changed
- Updated all documentation examples to include meaningful instance descriptions
- The `claude-swarm init` command now generates a template with description fields

## [0.1.3]

### Fixed
- Fixed duplicate prompt arguments being passed to Claude Code executor, which could cause command execution failures

### Changed
- Improved logging to track request flow between instances using `from_instance` and `to_instance` fields instead of generic `instance_name`
- Added required `calling_instance` parameter to MCP server command to properly identify the source of requests in tree configurations
- Consolidated session files into a single directory structure (`.claude-swarm/sessions/<timestamp>/`)
- MCP configuration files are now stored alongside session logs in the same timestamped directory
- Session logs are now named `session.log` instead of `session_<timestamp>.log`
- Improved organization by keeping all session-related files together

## [0.1.2] - 2025-05-29

### Added
- Added `-p` / `--prompt` flag to pass prompts directly to the main Claude instance for non-interactive mode
- Output suppression when running with the `-p` flag for cleaner scripted usage

## [0.1.1] - 2025-05-24

- Initial release
