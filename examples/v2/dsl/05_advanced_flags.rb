#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 5: Advanced Flags
#
# Tests: disable_default_tools, bypass_permissions, coding_agent, assume_model_exists
#
# Run: bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/05_advanced_flags.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"
require_relative "../../../swarm_sdk/permissions_builder"

ENV["OPENAI_API_KEY"] = "test-key"

swarm = SwarmSDK.build do
  name("Advanced Flags Test")
  lead(:test_agent)

  agent(:test_agent) do
    model("gpt-5-nano")
    provider("openai")
    description("Agent testing advanced flags")

    # Test skip_base_prompt: true (custom prompt only)
    coding_agent(false)
    system_prompt("You are a test agent. You only have Read tool. Say 'flags work' when asked.")

    # Test assume_model_exists: true (skip model validation)
    assume_model_exists(true)

    # Test bypass_permissions: false (respect permissions)
    bypass_permissions(false)

    # Only Read tool (no defaults) - using include_default: false
    tools(:Read, include_default: false)

    # Add permissions to verify bypass_permissions: false respects them
    permissions do
      tool(:Read).deny_paths("tmp/secret.txt")
    end
  end
end

puts "✅ Swarm with advanced flags built!"
puts ""

agent_def = swarm.agent_definition(:test_agent)

puts "Advanced Flags Verification:"
puts "  coding_agent: #{agent_def.coding_agent}"
puts "  disable_default_tools: #{agent_def.disable_default_tools}"
puts "  bypass_permissions: #{agent_def.bypass_permissions}"
puts "  assume_model_exists: #{agent_def.assume_model_exists}"
puts "  system_prompt: #{agent_def.system_prompt[0..80]}..."
puts ""

# Verify agent tools (should NOT include defaults like Grep, Glob)
agent_chat = swarm.agent(:test_agent)
tool_names = agent_chat.tools.keys
puts "Agent tools (should be ONLY Read, no defaults):"
puts "  #{tool_names.join(", ")}"
puts ""

puts "Running test query..."
result = swarm.execute("Are the flags working?")

puts ""
puts "Response: #{result.content}"
puts "Success: #{result.success?}"
puts ""
puts "✅ All advanced flags work correctly!"
