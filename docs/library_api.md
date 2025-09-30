# SwarmSDK Library API

**Version:** 2.0.0
**Purpose:** SwarmSDK as a standalone Ruby library
**Last Updated:** 2025-09-28

## Overview

SwarmSDK is designed as a **library-first** system. The CLI is a thin wrapper around the library API. This allows developers to:

- Embed SwarmSDK in Rails/Sinatra applications
- Build custom interfaces (web UI, API endpoints, etc.)
- Integrate with existing workflows
- Receive real-time structured logs of all LLM interactions

---

## Core Design Principles

1. **Library First, CLI Second**
   - All functionality lives in `SwarmSDK` module
   - CLI (`SwarmSDK::CLI`) is just one consumer of the library
   - No global state or CLI dependencies in core classes

2. **Event-Driven Logging**
   - Every LLM interaction emits structured JSON logs
   - Logs available via callback blocks
   - No coupling to stdout/files - consumer decides

3. **Async-Compatible**
   - All APIs work seamlessly with `Async` gem
   - Fiber-safe throughout
   - No blocking operations

---

## Basic Usage

### 1. Simple Swarm Execution

```ruby
require 'swarm_sdk'

# Load configuration
swarm = SwarmSDK::Swarm.load("swarm.yml")

# Execute with main agent
result = swarm.execute("Build user authentication system")

puts result.content
# => "I've implemented user authentication with JWT tokens..."

puts "Cost: $#{result.cost}"
# => "Cost: $0.0245"
```

### 2. With Real-Time Logging

```ruby
require 'swarm_sdk'

swarm = SwarmSDK::Swarm.load("swarm.yml")

# Receive logs as they happen
swarm.on_log do |log_entry|
  puts JSON.generate(log_entry)
  # Log to database, send to websocket, etc.
end

result = swarm.execute("Build feature")
```

### 3. Async Execution

```ruby
require 'async'
require 'swarm_sdk'

Async do
  swarm = SwarmSDK::Swarm.load("swarm.yml")

  # Execute multiple tasks concurrently
  tasks = [
    "Implement backend API",
    "Create frontend components",
    "Write tests"
  ].map do |task|
    Async { swarm.execute(task) }
  end

  results = tasks.map(&:wait)
  results.each { |r| puts r.content }
end
```

---

## API Reference

### SwarmSDK::Swarm

**Main entry point for library usage.**

#### Class Methods

```ruby
# Load swarm from YAML configuration
swarm = SwarmSDK::Swarm.load(config_path)
# => #<SwarmSDK::Swarm>

# Create from in-memory configuration
config = SwarmSDK::Configuration.load("swarm.yml")
swarm = SwarmSDK::Swarm.new(config)
```

#### Instance Methods

```ruby
# Execute task with main agent
result = swarm.execute(prompt, options = {})
# Options:
#   agent: String (default: main agent from config)
#   session_id: String (for session restoration)
#   metadata: Hash (attached to all logs)
# => #<SwarmSDK::Result>

# Execute with specific agent
result = swarm.execute("Task", agent: "backend")

# Get agent by name
agent = swarm.agent("backend")
# => #<SwarmSDK::Agent>

# List all agents
swarm.agents
# => [#<Agent: lead>, #<Agent: backend>, ...]

# Session management
session = swarm.save_session
# => #<SwarmSDK::Session id: "20250928-103045-abc123">

swarm.restore_session(session_id)
# => self

# Shutdown (cleanup resources)
swarm.shutdown
```

#### Event Hooks

```ruby
# Log events (called for every LLM interaction)
swarm.on_log do |log_entry|
  # log_entry is a Hash
  # type: "llm_request" | "llm_response" | "tool_call" | "tool_result"
  Rails.logger.info(log_entry.to_json)
end

# Agent started
swarm.on_agent_start do |agent_name, input|
  puts "#{agent_name} starting: #{input}"
end

# Agent completed
swarm.on_agent_complete do |agent_name, result|
  puts "#{agent_name} completed"
end

# Error handling
swarm.on_error do |error, context|
  Bugsnag.notify(error, context)
end
```

---

### SwarmSDK::Result

**Returned from `swarm.execute()`**

```ruby
result = swarm.execute("Task")

result.content        # String: final response
result.agent          # String: agent that produced result
result.cost           # Float: total cost in USD
result.tokens         # Hash: {input: X, output: Y, total: Z}
result.duration       # Float: seconds
result.logs           # Array<Hash>: all log entries
result.success?       # Boolean
result.error          # Exception or nil
result.metadata       # Hash: custom metadata
```

---

### SwarmSDK::Agent

**Direct agent access (advanced usage)**

```ruby
agent = swarm.agent("backend")

# Execute directly
result = agent.execute("Implement API endpoint")
# => #<SwarmSDK::Result>

# Access agent properties
agent.name            # String
agent.description     # String
agent.model           # String
agent.directory       # String
agent.connections     # Array<String>
agent.tools           # Array<String>

# Conversation history
agent.conversation_history
# => [{role: :user, content: "..."},
#     {role: :assistant, content: "..."}]

# Reset conversation
agent.reset!
```

---

### SwarmSDK::Session

**Session persistence and restoration**

```ruby
# Create session
session = swarm.save_session
# => #<SwarmSDK::Session>

session.id            # String: "20250928-103045-abc123"
session.created_at    # Time
session.swarm_name    # String
session.total_cost    # Float
session.total_tokens  # Hash
session.agents        # Array<String>

# List sessions
sessions = SwarmSDK::Session.all
# => [#<Session>, #<Session>, ...]

# Load session
session = SwarmSDK::Session.find(session_id)
swarm.restore_session(session)

# Delete session
session.destroy
```

---

## Unified Logging Format

All log entries are structured JSON emitted via the `on_log` hook.

### Log Types

#### 1. LLM Request

```json
{
  "timestamp": "2025-09-28T10:30:00.123Z",
  "type": "llm_request",
  "agent": "backend",
  "model": "claude-3-5-sonnet-20241022",
  "provider": "anthropic",
  "message_count": 3,
  "tools": ["Read", "Edit", "call_agent__database"],
  "metadata": {"session_id": "abc123", "user_id": 42}
}
```

#### 2. LLM Response

```json
{
  "timestamp": "2025-09-28T10:30:01.456Z",
  "type": "llm_response",
  "agent": "backend",
  "model": "claude-3-5-sonnet-20241022",
  "content": "I'll query the database for you.",
  "tool_calls": [
    {
      "id": "toolu_01ABC123",
      "name": "call_agent__database",
      "arguments": {"query": "SELECT * FROM users"}
    }
  ],
  "finish_reason": "tool_calls",
  "usage": {
    "input_tokens": 150,
    "output_tokens": 45,
    "total_tokens": 195
  },
  "metadata": {"session_id": "abc123"}
}
```

#### 3. Tool Call

```json
{
  "timestamp": "2025-09-28T10:30:01.500Z",
  "type": "tool_call",
  "agent": "backend",
  "tool_call_id": "toolu_01ABC123",
  "tool": "call_agent__database",
  "arguments": {"query": "SELECT * FROM users"},
  "metadata": {"session_id": "abc123"}
}
```

#### 4. Tool Result

```json
{
  "timestamp": "2025-09-28T10:30:02.234Z",
  "type": "tool_result",
  "agent": "backend",
  "tool_call_id": "toolu_01ABC123",
  "result": {"users": [{"id": 1, "name": "Alice"}]},
  "metadata": {"session_id": "abc123"}
}
```

---

## Integration Examples

### Rails Application

```ruby
# app/services/swarm_service.rb
class SwarmService
  def self.execute_task(task, user:)
    swarm = SwarmSDK::Swarm.load(Rails.root.join("config/swarm.yml"))

    # Log to Rails logger
    swarm.on_log do |log|
      Rails.logger.info("[SwarmSDK] #{log.to_json}")
    end

    # Track in database
    execution = SwarmExecution.create!(
      user: user,
      task: task,
      status: :running
    )

    swarm.on_agent_complete do |agent_name, result|
      execution.agent_results.create!(
        agent: agent_name,
        content: result.content,
        cost: result.cost
      )
    end

    result = swarm.execute(
      task,
      metadata: { user_id: user.id, execution_id: execution.id }
    )

    execution.update!(
      status: :completed,
      result: result.content,
      total_cost: result.cost
    )

    result
  rescue => e
    execution.update!(status: :failed, error: e.message)
    raise
  ensure
    swarm.shutdown
  end
end

# app/controllers/tasks_controller.rb
class TasksController < ApplicationController
  def create
    result = SwarmService.execute_task(
      params[:task],
      user: current_user
    )

    render json: {
      result: result.content,
      cost: result.cost,
      duration: result.duration
    }
  end
end
```

### Background Jobs

```ruby
# app/jobs/swarm_job.rb
class SwarmJob < ApplicationJob
  queue_as :swarm

  def perform(task, user_id)
    swarm = SwarmSDK::Swarm.load("config/swarm.yml")

    # Stream logs to ActionCable
    swarm.on_log do |log|
      ActionCable.server.broadcast(
        "swarm_#{job_id}",
        log
      )
    end

    result = swarm.execute(task, metadata: { user_id: user_id })

    SwarmMailer.completion_email(user_id, result).deliver_later
  ensure
    swarm.shutdown
  end
end
```

### WebSocket Streaming

```ruby
# app/channels/swarm_channel.rb
class SwarmChannel < ApplicationCable::Channel
  def subscribed
    stream_from "swarm_#{params[:session_id]}"
  end

  def execute(data)
    swarm = SwarmSDK::Swarm.load("config/swarm.yml")

    # Stream all logs to WebSocket
    swarm.on_log do |log|
      transmit(log)
    end

    # Execute in background
    Async do
      result = swarm.execute(data["task"])
      transmit(type: "complete", result: result.content)
    end
  end
end
```

### API Endpoint

```ruby
# app/controllers/api/v1/swarm_controller.rb
module API
  module V1
    class SwarmController < ApplicationController
      def execute
        swarm = SwarmSDK::Swarm.load("config/swarm.yml")
        logs = []

        swarm.on_log { |log| logs << log }

        result = swarm.execute(
          params[:task],
          agent: params[:agent],
          metadata: { api_key: current_api_key }
        )

        render json: {
          content: result.content,
          cost: result.cost,
          tokens: result.tokens,
          duration: result.duration,
          logs: logs
        }
      ensure
        swarm.shutdown
      end
    end
  end
end
```

### Concurrent Execution

```ruby
# Execute multiple swarms in parallel
require 'async'

Async do
  backend_swarm = SwarmSDK::Swarm.load("backend_swarm.yml")
  frontend_swarm = SwarmSDK::Swarm.load("frontend_swarm.yml")

  results = Async::Barrier.new do |barrier|
    barrier.async do
      backend_swarm.execute("Build API")
    end

    barrier.async do
      frontend_swarm.execute("Build UI")
    end
  end.wait

  puts "Backend: #{results[0].content}"
  puts "Frontend: #{results[1].content}"
end
```

---

## CLI Implementation

The CLI is a thin wrapper around the library:

```ruby
# lib/swarm_sdk/cli.rb
module SwarmSDK
  class CLI < Thor
    desc "start [CONFIG]", "Start swarm"
    option :prompt, type: :string
    def start(config_path = "swarm.yml")
      swarm = Swarm.load(config_path)

      # Pretty print logs to stdout
      swarm.on_log do |log|
        print_log(log)
      end

      result = swarm.execute(options[:prompt])

      puts "\n" + "="*80
      puts result.content
      puts "\nCost: $#{result.cost}"
      puts "Tokens: #{result.tokens[:total]}"
    ensure
      swarm.shutdown
    end

    private

    def print_log(log)
      case log[:type]
      when "llm_request"
        puts "🤔 #{log[:agent]} thinking... (#{log[:model]})"
      when "llm_response"
        puts "💬 #{log[:agent]}: #{log[:content]}" if log[:content]
      when "tool_call"
        puts "🔧 #{log[:agent]} → #{log[:tool]}"
      end
    end
  end
end
```

---

## Testing

### Unit Tests

```ruby
require 'test_helper'

class SwarmTest < Minitest::Test
  def test_execute_returns_result
    swarm = SwarmSDK::Swarm.load("test/fixtures/simple_swarm.yml")

    result = swarm.execute("Hello")

    assert_kind_of SwarmSDK::Result, result
    assert result.success?
    assert result.content.is_a?(String)
  ensure
    swarm.shutdown
  end

  def test_logs_are_emitted
    swarm = SwarmSDK::Swarm.load("test/fixtures/simple_swarm.yml")
    logs = []

    swarm.on_log { |log| logs << log }
    swarm.execute("Hello")

    assert logs.any? { |l| l[:type] == "llm_request" }
    assert logs.any? { |l| l[:type] == "llm_response" }
  ensure
    swarm.shutdown
  end
end
```

### Integration Tests with Mocks

```ruby
def test_with_mocked_llm
  llm_mock = SwarmSDK::LLMMock.new
  llm_mock.add_response(content: "Mocked response")

  swarm = SwarmSDK::Swarm.load(
    "test/fixtures/swarm.yml",
    llm_client: llm_mock
  )

  result = swarm.execute("Test task")

  assert_equal "Mocked response", result.content
ensure
  swarm.shutdown
end
```

---

## Error Handling

```ruby
begin
  swarm = SwarmSDK::Swarm.load("swarm.yml")
  result = swarm.execute("Task")
rescue SwarmSDK::ConfigurationError => e
  puts "Config error: #{e.message}"
rescue SwarmSDK::LLMError => e
  puts "LLM error: #{e.message}"
rescue SwarmSDK::AgentNotFoundError => e
  puts "Agent error: #{e.message}"
ensure
  swarm&.shutdown
end
```

---

## Performance Considerations

### Memory Usage

```ruby
# 20 agents × 4KB fibers = 80KB overhead
swarm = SwarmSDK::Swarm.load("large_swarm.yml")

puts "Agents: #{swarm.agents.count}"
# => "Agents: 20"

# All execute concurrently during I/O
swarm.execute("Analyze codebase")
# Memory: ~50MB total (single Ruby process + fibers)
```

### Concurrent Execution

```ruby
# Execute multiple tasks with same swarm instance
Async do
  swarm = SwarmSDK::Swarm.load("swarm.yml")

  tasks = 10.times.map do |i|
    Async do
      swarm.execute("Task #{i}")
    end
  end

  results = tasks.map(&:wait)
  # All 10 tasks execute concurrently
  # Limited only by API rate limits
end
```

---

## Summary

**Library-First Design:**
- ✅ No CLI coupling
- ✅ All functionality in `SwarmSDK` module
- ✅ Event-driven logging via callbacks
- ✅ Async-compatible throughout

**Integration:**
- ✅ Rails/Sinatra applications
- ✅ Background jobs
- ✅ WebSocket streaming
- ✅ API endpoints
- ✅ Custom interfaces

**Logging:**
- ✅ Structured JSON format
- ✅ Real-time via callbacks
- ✅ Provider-agnostic (RubyLLM normalizes)
- ✅ Consumer decides destination

The CLI is just one thin wrapper around this powerful library API.

---

**Document Version:** 1.0
**Author:** SwarmSDK Team
**Last Updated:** 2025-09-28