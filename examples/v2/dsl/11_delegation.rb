#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 11: Agent Delegation
#
# Tests: Multi-agent delegation with delegates_to
#
# Run: bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/11_delegation.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"

ENV["OPENAI_API_KEY"] = "test-key"

swarm = SwarmSDK.build do
  name("Delegation Test")
  lead(:coordinator)

  agent(:coordinator) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You coordinate tasks. Delegate math to calculator, text to writer.")
    description("Coordinator")
    tools(:TodoWrite)
    delegates_to(:calculator, :writer)
  end

  agent(:calculator) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You do math. Answer with just the number.")
    description("Math specialist")
    tools(:Read)
  end

  agent(:writer) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You write text. Be creative and concise.")
    description("Writing specialist")
    tools(:Read)
  end
end

puts "✅ Swarm with delegation built!"
puts ""

coordinator_def = swarm.agent_definition(:coordinator)
puts "Coordinator can delegate to: #{coordinator_def.delegates_to.join(", ")}"
puts ""

puts "Testing multi-agent delegation..."
result = swarm.execute("Delegate to calculator: what is 7 + 8? Then delegate to writer: write a haiku about swarms")

puts ""
puts "Response: #{result.content}"
puts "Success: #{result.success?}"
puts ""
puts "✅ Delegation works!"
