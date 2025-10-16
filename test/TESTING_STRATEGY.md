# SwarmSDK Testing Strategy

## Overview

SwarmSDK tests use **WebMock** to mock HTTP requests to LLM APIs, avoiding real API calls while still testing the full integration with RubyLLM.

## Why Mock at the HTTP Layer?

### Benefits ✅

1. **Tests full RubyLLM integration** - Tests the entire call chain from AgentChat through RubyLLM
2. **Tests SwarmSDK extensions** - Verifies parallel tool calling, semaphores, and rate limiting
3. **Tests message history** - Ensures conversation state is managed correctly
4. **Tests callbacks** - Verifies `on_tool_call`, `on_end_message` callbacks work
5. **Enables error testing** - Can test timeouts, network errors, API errors
6. **Most realistic** - Only mocks the external boundary (HTTP)
7. **Standard practice** - WebMock is the Ruby standard for HTTP mocking

### What's NOT Mocked ❌

- SwarmSDK code (Swarm, AgentChat, tools, etc.)
- RubyLLM gem internals
- Async execution and semaphores
- Message history and state management
- Tool calling flow

### What IS Mocked ✅

- HTTP requests to LLM API endpoints (OpenAI, Anthropic, etc.)
- Network errors and timeouts (when testing error handling)
- API error responses (rate limits, auth errors, etc.)

## Test Helpers

### LLMMockHelper Module

Located at `test/helpers/llm_mock_helper.rb`

Provides convenient methods for mocking LLM API responses:

#### `mock_llm_response(content:, model:, tool_calls:)`

Creates an OpenAI-compatible API response structure.

```ruby
# Simple text response
response = mock_llm_response(content: "Hello, world!")

# Response with tool calls
response = mock_llm_response(
  tool_calls: [
    { name: "backend", arguments: { task: "Build API" } }
  ]
)
```

#### `stub_llm_request(response, times:, url_pattern:)`

Stubs a single HTTP request to return a specific response.

```ruby
# Stub one request
stub_llm_request(mock_llm_response(content: "Test response"))

# Stub multiple identical requests
stub_llm_request(mock_llm_response(content: "Test"), times: 3)

# Stub custom URL pattern
stub_llm_request(
  mock_llm_response(content: "Test"),
  url_pattern: %r{https://custom\.proxy/.*}
)
```

#### `stub_llm_sequence(*responses)`

Stubs multiple sequential HTTP requests with different responses.

Useful for testing tool call loops where:
1. LLM makes tool calls
2. Tools execute and return results
3. LLM generates final response

```ruby
stub_llm_sequence(
  mock_llm_response(tool_calls: [{ name: "backend", arguments: { task: "Build" } }]),
  mock_llm_response(content: "Backend complete"),
  mock_llm_response(content: "All done!")
)
```

#### Error Helpers

```ruby
# Stub timeout error
stub_llm_timeout

# Stub network error
stub_llm_network_error

# Stub API error (rate limit, auth, etc.)
stub_llm_error(
  error_code: "rate_limit_exceeded",
  message: "Too many requests",
  status: 429
)
```

## Example Tests

### Basic Execution Test

```ruby
def test_execute_returns_result
  swarm = Swarm.new(name: "Test Swarm")
  swarm.add_agent(
    name: :lead,
    description: "Lead agent",
    model: "gpt-5",
    system_prompt: "You are a test agent",
    directories: ["."]
  )
  swarm.lead = :lead

  # Mock the HTTP response
  stub_llm_request(mock_llm_response(content: "Task completed"))

  result = swarm.execute("Do something")

  assert_predicate(result, :success?)
  assert_equal("Task completed", result.content)
  assert_equal("lead", result.agent)
end
```

### Tool Delegation Test

```ruby
def test_delegation_flow
  swarm = Swarm.new(name: "Test")
  swarm.add_agent(
    name: :lead,
    description: "Lead",
    model: "gpt-5",
    system_prompt: "Lead agent",
    delegates_to: [:backend],
    directories: ["."]
  )
  swarm.add_agent(
    name: :backend,
    description: "Backend developer",
    model: "gpt-5",
    system_prompt: "Backend agent",
    directories: ["."]
  )
  swarm.lead = :lead

  # Mock the sequence:
  # 1. Lead decides to call backend tool
  # 2. Backend agent responds
  # 3. Lead synthesizes final answer
  stub_llm_sequence(
    mock_llm_response(
      tool_calls: [{ name: "backend", arguments: { task: "Build API" } }]
    ),
    mock_llm_response(content: "API built successfully"),
    mock_llm_response(content: "All tasks completed")
  )

  result = swarm.execute("Build authentication API")

  assert_predicate(result, :success?)
  assert_equal("All tasks completed", result.content)
end
```

### Error Handling Test

```ruby
def test_handles_timeout_gracefully
  swarm = Swarm.new(name: "Test")
  swarm.add_agent(
    name: :lead,
    description: "Lead",
    model: "gpt-5",
    system_prompt: "Test",
    directories: ["."]
  )
  swarm.lead = :lead

  # Mock timeout error
  stub_llm_timeout

  result = swarm.execute("Do something")

  assert_predicate(result, :failure?)
  assert_instance_of(Faraday::TimeoutError, result.error)
end
```

## Exception: Ruby-Level Mocking for Error Handling Tests

Some tests mock at the Ruby method level using `define_singleton_method`. This is appropriate when:

1. **Testing SwarmSDK's error handling logic** - Not testing HTTP/network layer
2. **Testing error transformation** - e.g., TypeError → LLMError conversion
3. **Simulating internal errors** - Errors that wouldn't come from HTTP

### Example: Testing Error Handling Logic

```ruby
def test_execute_with_error_returns_failed_result
  swarm = Swarm.new(name: "Test Swarm")
  swarm.add_agent(
    name: :lead,
    description: "Lead",
    model: "gpt-5",
    system_prompt: "Test",
    directories: ["."]
  )
  swarm.lead = :lead

  # Mock at Ruby level to test SwarmSDK error handling
  swarm.send(:initialize_agents)
  lead_agent = swarm.agent(:lead)

  lead_agent.define_singleton_method(:ask) do |_prompt|
    raise StandardError, "Test error"
  end

  result = swarm.execute("test prompt")

  assert_predicate(result, :failure?)
  assert_instance_of(StandardError, result.error)
  assert_equal("Test error", result.error.message)
end
```

**Rationale:** This test verifies that SwarmSDK properly catches errors and wraps them in a Result object. The source of the error (HTTP vs Ruby) is irrelevant to what's being tested.

## Configuration

WebMock is configured in `test/test_helper.rb`:

```ruby
require "webmock/minitest"

# Configure WebMock to block all external HTTP requests except localhost
WebMock.disable_net_connect!(allow_localhost: true)

# Include LLM mocking helpers in all tests
module Minitest
  class Test
    include LLMMockHelper
  end
end
```

This ensures:
- No accidental real API calls (tests will fail if attempted)
- Localhost connections still work (for any local services)
- All tests have access to helper methods

## Best Practices

### ✅ DO

- **Use WebMock for LLM API mocking** - Standard, maintainable, realistic
- **Test real SwarmSDK logic** - Don't mock internal SwarmSDK code
- **Test tool execution** - Let real tools run with controlled inputs
- **Use temp files for file I/O** - Already done in tool tests
- **Mock at Ruby level for error handling tests** - When appropriate

### ❌ DON'T

- **Make real API calls in tests** - Slow, flaky, costs money
- **Mock internal SwarmSDK methods** - Defeats the purpose of testing
- **Over-mock** - Only mock external boundaries
- **Mock RubyLLM internals** - Test through the public API

## Test Isolation

Each test is automatically isolated:

1. **WebMock resets between tests** - No stub pollution
2. **Temp directories per test** - No file conflicts
3. **Independent ENV setup/teardown** - No state leakage
4. **Fresh Swarm instances** - No shared state

## Running Tests

```bash
# Run all SwarmSDK tests
bundle exec rake swarm_sdk:test

# Run all tests
bundle exec rake test

# Run specific test file
bundle exec ruby test/swarm_sdk/swarm_test.rb

# Run specific test
bundle exec ruby test/swarm_sdk/swarm_test.rb -n test_execute_returns_result_instance
```

## Coverage

Current test coverage: **~85%** line coverage, **~72%** branch coverage

The test suite covers:
- ✅ Swarm initialization and configuration
- ✅ Agent management
- ✅ Execution flow
- ✅ Tool delegation
- ✅ Error handling
- ✅ Parallel tool execution
- ✅ Rate limiting (semaphores)
- ✅ Message history
- ✅ Result wrapping

## Future Enhancements

Potential improvements:

1. **VCR integration** - Record real API calls during development, replay in tests
2. **More delegation tests** - Complex multi-agent scenarios
3. **Streaming tests** - Verify streaming callbacks work correctly
4. **Performance tests** - Benchmark concurrency and rate limiting
5. **Integration tests** - End-to-end scenarios with real tools

## Conclusion

The testing strategy balances:
- **Realism** - Tests real integration with RubyLLM
- **Isolation** - No external dependencies or real API calls
- **Maintainability** - Standard Ruby patterns with WebMock
- **Coverage** - Comprehensive testing of SwarmSDK logic

By mocking at the HTTP layer, we test everything except the actual LLM API, which is the responsibility of RubyLLM gem and LLM providers.
