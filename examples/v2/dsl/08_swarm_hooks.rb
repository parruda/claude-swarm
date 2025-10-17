#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 8: Swarm-Level Hooks
#
# Tests: hook :swarm_start, hook :swarm_stop (Ruby blocks)
#
# Run: VAULT_TOKEN=xxx bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/08_swarm_hooks.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"

ENV["OPENAI_API_KEY"] = "test-key"

swarm = SwarmSDK.build do
  name("Swarm Hooks Test")
  lead(:agent)

  # Swarm-level hook: swarm_start
  hook(:swarm_start) do |ctx|
    puts "🪝 swarm_start hook fired!"
    puts "   Prompt: #{ctx.metadata[:prompt]}"
  end

  # Swarm-level hook: swarm_stop
  hook(:swarm_stop) do |ctx|
    puts "🪝 swarm_stop hook fired!"
    puts "   Success: #{ctx.metadata[:success]}"
    puts "   Cost: $#{ctx.metadata[:total_cost]}"
  end

  agent(:agent) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You test swarm hooks. Say 'hooks work'.")
    description("Test agent")
    tools(:Read)
  end
end

puts "✅ Swarm with swarm-level hooks built!"
puts ""
puts "Running execution to trigger hooks..."
puts ""

result = swarm.execute("Say 'swarm hooks test'")

puts ""
puts "Response: #{result.content}"
puts ""
puts "✅ Swarm-level hooks work correctly!"
puts "(Check output above for 🪝 markers)"
