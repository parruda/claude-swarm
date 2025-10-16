#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 9: Agent-Level Hooks
#
# Tests: hook :pre_tool_use, hook :post_tool_use, hook :user_prompt (Ruby blocks)
#
# Run: VAULT_TOKEN=xxx bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/09_agent_hooks.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"

ENV["OPENAI_API_KEY"] = ENV["VAULT_TOKEN"]

swarm = SwarmSDK.build do
  name("Agent Hooks Test")
  lead(:agent)

  agent(:agent) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You test agent hooks. Use Read tool to read tmp/test.txt")
    description("Test agent with hooks")
    tools(:Read)

    # Hook: user_prompt (before sending to LLM)
    hook(:user_prompt) do |ctx|
      puts "🪝 user_prompt hook fired!"
      puts "   Prompt: #{ctx.metadata[:prompt][0..50]}..."
    end

    # Hook: pre_tool_use (before tool execution)
    hook(:pre_tool_use, matcher: "Read") do |ctx|
      puts "🪝 pre_tool_use hook fired!"
      puts "   Tool: #{ctx.tool_call.name}"
      puts "   File: #{ctx.tool_call.parameters[:file_path]}"
    end

    # Hook: post_tool_use (after tool execution)
    hook(:post_tool_use, matcher: "Read") do |ctx|
      puts "🪝 post_tool_use hook fired!"
      puts "   Result length: #{ctx.tool_result.content.to_s.length} chars"
    end
  end
end

# Setup test file
require "fileutils"
FileUtils.mkdir_p("tmp")
File.write("tmp/test.txt", "test content for hooks")

puts "✅ Swarm with agent-level hooks built!"
puts ""
puts "Running execution to trigger hooks..."
puts ""

result = swarm.execute("Read the file tmp/test.txt")

puts ""
puts "Response: #{result.content}"
puts ""
puts "✅ Agent-level hooks work correctly!"
puts "(Hooks fired - check output above for 🪝 markers)"

# Cleanup
File.delete("tmp/test.txt") if File.exist?("tmp/test.txt")
