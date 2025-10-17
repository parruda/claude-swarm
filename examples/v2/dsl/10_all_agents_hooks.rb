#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 10: All-Agents Hooks
#
# Tests: all_agents { hook } (applies to all agents)
#
# Run: VAULT_TOKEN=xxx bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/10_all_agents_hooks.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"
require_relative "../../../swarm_sdk/all_agents_builder"

ENV["OPENAI_API_KEY"] = "test-key"

swarm = SwarmSDK.build do
  name("All-Agents Hooks Test")
  lead(:agent1)

  # Hook that applies to ALL agents
  all_agents do
    hook(:pre_tool_use, matcher: "Read") do |ctx|
      agent = ctx.agent_name
      puts "🪝 all_agents hook fired for: #{agent}"
      puts "   Tool: #{ctx.tool_call.name}"
    end
  end

  agent(:agent1) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You test all_agents hooks. Use Read tool. Delegate to agent2.")
    description("First test agent")
    tools(:Read)
    delegates_to(:agent2)
  end

  agent(:agent2) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You are agent2. Use Read tool when asked.")
    description("Second test agent")
    tools(:Read)
  end
end

# Setup test file
require "fileutils"
FileUtils.mkdir_p("tmp")
File.write("tmp/all_agents_test.txt", "testing all_agents hooks")

puts "✅ Swarm with all_agents hooks built!"
puts ""
puts "Running execution to trigger hooks across agents..."
puts ""

result = swarm.execute("Read tmp/all_agents_test.txt, then delegate to agent2 to also read it")

puts ""
puts "Response: #{result.content[0..150]}..."
puts ""
puts "✅ All-agents hooks work correctly!"
puts "(Check output above for 🪝 markers showing hook fired for multiple agents)"

# Cleanup
File.delete("tmp/all_agents_test.txt") if File.exist?("tmp/all_agents_test.txt")
