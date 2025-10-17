#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 1: Basic Swarm Configuration
#
# Tests: name, lead, basic agent with minimal config
#
# Run: bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/01_basic.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"

ENV["OPENAI_API_KEY"] = "test-key"

swarm = SwarmSDK.build do
  name("Basic Test Swarm")
  lead(:simple_agent)

  agent(:simple_agent) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You are a simple test agent. Answer questions concisely.")
    description("Simple agent for basic DSL testing")
    tools(:Read)
  end
end

puts "✅ Swarm built successfully!"
puts "Name: #{swarm.name}"
puts "Lead: #{swarm.lead_agent}"
puts "Agents: #{swarm.agent_names.join(", ")}"
puts ""
puts "Running test query..."

result = swarm.execute("What is 2 + 2?")

puts ""
puts "Result: #{result.content}"
puts "Success: #{result.success?}"
puts "Duration: #{result.duration}s"
puts "Cost: $#{result.total_cost}"
puts ""
puts "✅ Basic configuration works!"
