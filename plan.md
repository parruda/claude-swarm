# OpenAI Provider Support Implementation Plan

## Overview
Add support for OpenAI as a provider in Claude Swarm, allowing instances to be powered by OpenAI models (GPT-4, etc.) while maintaining the same swarm orchestration capabilities.

## Key Requirements
1. Reuse existing `ClaudeMcpServer` infrastructure
2. Support both OpenAI Chat Completions API and Responses API
3. OpenAI instances use MCP for tool access via `claude mcp serve` and `ruby-mcp-client`
4. Maintain existing session logging (session.log and session.log.json)
5. Provider field is optional (defaults to Claude behavior)
6. OpenAI-specific fields only accepted when provider is "openai"

## Architecture Design

### 1. OpenAIExecutor Class
- Parallel to `ClaudeCodeExecutor`
- Implements same interface for compatibility
- Uses `ruby-openai` gem for API calls
- Uses `ruby-mcp-client` for tool access
- Supports both chat completions and responses API
- Handles streaming responses
- Maintains session state and logging

### 2. Configuration Updates
New instance fields (only valid when provider: "openai"):
- `provider` - Optional, values: "claude" (default) or "openai"
- `temperature` - Optional, default: 0.3
- `api_version` - Optional, values: "chat_completion" (default) or "responses"
- `openai_token_env` - Optional, default: "OPENAI_API_KEY"
- `base_url` - Optional, default: ruby-openai default

### 3. MCP Integration for Tools
OpenAI instances will:
1. Launch their own MCP server via `claude mcp serve`
2. Connect to it using `ruby-mcp-client`
3. List available tools and convert to OpenAI format
4. Execute tools via MCP when OpenAI requests them

## Implementation Steps

### Phase 1: Dependencies and Core Classes
1. Update Gemfile with ruby-openai and ruby-mcp-client
2. Create OpenAIExecutor class structure
3. Implement basic chat completion functionality

### Phase 2: Configuration and Validation
1. Update Configuration class to parse new fields
2. Add validation for OpenAI-specific fields
3. Ensure backward compatibility

### Phase 3: MCP Server Integration
1. Update ClaudeMcpServer to support provider-based executor
2. Modify MCP Generator to pass provider parameters
3. Update CLI with new options

### Phase 4: Tool Integration
1. Implement MCP client connection in OpenAIExecutor
2. Add tool listing and conversion
3. Implement tool execution flow

### Phase 5: Responses API Support
1. Add responses API implementation
2. Handle conversation threading with previous_response_id
3. Implement response management (retrieve, delete)

### Phase 6: Testing and Documentation
1. Create comprehensive unit tests
2. Add integration tests
3. Update existing tests for backward compatibility
4. Test end-to-end functionality

## File Changes

### New Files:
- `lib/claude_swarm/openai_executor.rb` - OpenAI API executor
- `test/openai_executor_test.rb` - OpenAI executor tests

### Modified Files:
- `Gemfile` - Add dependencies
- `lib/claude_swarm.rb` - Require new files
- `lib/claude_swarm/configuration.rb` - Add OpenAI fields and validation
- `lib/claude_swarm/claude_mcp_server.rb` - Add provider support
- `lib/claude_swarm/mcp_generator.rb` - Pass provider parameters
- `lib/claude_swarm/cli.rb` - Add provider options
- Various test files - Update for provider support

## Testing Strategy

### Unit Tests:
- OpenAIExecutor initialization
- API request formatting
- Tool conversion and execution
- Session management
- Error handling

### Integration Tests:
- Full swarm with mixed Claude/OpenAI instances
- Tool calling between instances
- Session restoration
- Both API versions (chat_completion and responses)

### Manual Testing:
- Use provided Shopify proxy for real API testing
- Test various model configurations
- Verify logging and session tracking

## Security Considerations
- Never commit API keys or tokens
- Never commit test base URLs
- Use environment variables for sensitive data
- Add .env to .gitignore if needed

## Progress Tracking

### Completed:
- [x] Initial research and planning
- [x] Consultation with experts
- [x] Architecture design
- [x] Writing plan.md
- [x] Dependency updates (already in gemspec)
- [x] OpenAIExecutor implementation
- [x] Configuration updates
- [x] MCP integration (ClaudeMcpServer updated)
- [x] CLI updates
- [x] Created comprehensive tests
- [x] Updated existing tests
- [x] Running tests and fixing issues
- [x] Documentation updates in README

### In Progress:
None

### Pending:
None

### Complete!
All tasks have been successfully completed. PR #41 has been created at:
https://github.com/parruda/claude-swarm/pull/41

## Notes
- Default to vibe: true for OpenAI instances (as specified)
- OpenAI instances don't support allowed_tools/disallowed_tools initially
- Focus on maintaining backward compatibility
- Keep session logging format consistent across providers