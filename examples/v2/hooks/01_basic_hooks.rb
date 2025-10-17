#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic Hooks Example - Beginner Level
#
# This example demonstrates the fundamentals of SwarmSDK's hook system:
# - What hooks are and when they fire
# - Simple validation hooks
# - Logging hooks
# - Blocking operations with hooks
#
# Run: bundle exec ruby -Ilib lib/swarm_sdk/examples/hooks/01_basic_hooks.rb

require "swarm_sdk"

puts "=" * 80
puts "BASIC HOOKS EXAMPLE"
puts "=" * 80
puts ""

# Create a simple swarm with hooks
swarm = SwarmSDK.build do
  name("Basic Hooks Demo")
  lead(:assistant)

  # Swarm-level hook: fires before any tool is used
  hook(:pre_tool_use) do |context|
    puts "🔧 About to use tool: #{context.tool_name}"
  end

  # Swarm-level hook: fires after any tool completes
  hook(:post_tool_use) do |context|
    if context.tool_result.success?
      puts "✅ Tool #{context.tool_name} succeeded"
    else
      puts "❌ Tool #{context.tool_name} failed"
    end
  end

  agent(:assistant) do
    description("A simple assistant with validation hooks")
    model("gpt-4o")
    system_prompt(<<~PROMPT)
      You are a helpful assistant. You can read and write files.
      When asked to create files, use the Write tool.
    PROMPT

    tools(:Write)

    # Agent-specific hook: validate Write operations
    hook(:pre_tool_use, matcher: "Write") do |context|
      file_path = context.tool_call.parameters[:file_path]
      content = context.tool_call.parameters[:content]

      puts "🔍 Validating write operation..."
      puts "   File: #{file_path}"
      puts "   Content size: #{content&.length || 0} bytes"

      # Block empty content
      if content.nil? || content.strip.empty?
        SwarmSDK::Hooks::Result.halt("Cannot write empty content")
      end

      # Block certain file extensions
      if file_path&.end_with?(".key", ".pem", ".secret")
        SwarmSDK::Hooks::Result.halt("Cannot write sensitive file types")
      end

      puts "   ✓ Validation passed"
    end
  end
end

# Example 1: Successful operation
puts "\n--- Example 1: Valid Write Operation ---"
begin
  result = swarm.execute("Create a file called test.txt with 'Hello World'")
  puts "\nResult: #{result.success? ? "SUCCESS" : "FAILED"}"
  puts "Response: #{result.content[0..100]}..."
rescue => e
  puts "\nError: #{e.message}"
end

# Example 2: Blocked - empty content
puts "\n\n--- Example 2: Blocked - Empty Content ---"
begin
  result = swarm.execute("Create a file called empty.txt with no content")
  puts "\nResult: #{result.success? ? "SUCCESS" : "FAILED"}"
  puts "Response: #{result.content[0..200]}..."
rescue => e
  puts "\nError: #{e.message}"
end

# Example 3: Blocked - sensitive file
puts "\n\n--- Example 3: Blocked - Sensitive File Type ---"
begin
  result = swarm.execute("Create a file called secret.key with 'API_KEY=123'")
  puts "\nResult: #{result.success? ? "SUCCESS" : "FAILED"}"
  puts "Response: #{result.content[0..200]}..."
rescue => e
  puts "\nError: #{e.message}"
end

puts "\n" + "=" * 80
puts "KEY TAKEAWAYS"
puts "=" * 80
puts <<~SUMMARY

  1. **pre_tool_use hooks** run before tools execute
     - Perfect for validation and security checks
     - Can halt execution with Hooks::Result.halt()

  2. **post_tool_use hooks** run after tools complete
     - Access results via context.tool_result
     - Check success/failure status

  3. **Matchers** target specific tools
     - matcher: "Write" - only Write tool
     - matcher: "Write|Edit" - Write OR Edit
     - No matcher = all tools

  4. **Hook levels**:
     - Swarm-level (all agents): hook :event_name
     - Agent-specific: Inside agent block

  5. **Halting execution**:
     - SwarmSDK::Hooks::Result.halt("reason")
     - Returns error message to agent
     - Agent sees tool failure, not code exception

SUMMARY

puts "=" * 80
