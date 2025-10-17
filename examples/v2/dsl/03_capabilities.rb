#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 3: Agent Capabilities
#
# Tests: tools, delegates_to, directory
#
# Run: bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/03_capabilities.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"

ENV["OPENAI_API_KEY"] = "test-key"

swarm = SwarmSDK.build do
  name("Capabilities Test")
  lead(:coordinator)

  agent(:coordinator) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You coordinate work and delegate to workers. Use TodoWrite for multi-step tasks.")
    description("Coordinator testing delegation")

    # Multiple tools
    tools(:Read, :Grep, :Glob, :TodoWrite)

    # Delegation
    delegates_to(:worker)

    # Working directory
    directory(".")
  end

  agent(:worker) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You are a worker agent. Answer concisely.")
    description("Worker agent for delegation testing")

    tools(:Read)
  end
end

puts "✅ Swarm with capabilities built!"
puts ""

# Verify configuration using public API
coordinator_def = swarm.agent_definition(:coordinator)
worker_def = swarm.agent_definition(:worker)

puts "Coordinator:"
puts "  tools: #{coordinator_def.tools.map { |t| t[:name] }.join(", ")}"
puts "  delegates_to: #{coordinator_def.delegates_to.join(", ")}"
puts "  directory: #{coordinator_def.directory}"
puts ""

puts "Worker:"
puts "  tools: #{worker_def.tools.map { |t| t[:name] }.join(", ")}"
puts ""

puts "Testing delegation..."
result = swarm.execute("Delegate a simple task to the worker: ask them what 5 + 3 equals")

puts ""
puts "Response: #{result.content}"
puts "Agents involved: #{result.agents_involved.join(", ")}"
puts "Success: #{result.success?}"
puts ""
puts "✅ Tools, delegation, and directory work!"
