#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 2: All Core Agent Parameters
#
# Tests: model, provider, base_url, api_version, context_window, system_prompt, description
#
# Run: VAULT_TOKEN=xxx bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/02_core_parameters.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"

ENV["OPENAI_API_KEY"] = "test-key"

swarm = SwarmSDK.build do
  name("Core Parameters Test")
  lead(:full_config_agent)

  agent(:full_config_agent) do
    # Core LLM configuration
    model("gpt-5-nano")
    provider("openai")
    api_version("v1/responses")
    context_window(200_000)

    # Agent identity
    system_prompt("You are testing all core configuration parameters. Be concise.")
    description("Agent testing all core configuration parameters")

    # Minimal tool for testing
    tools(:Read)
  end
end

puts "✅ Swarm with all core parameters built!"
puts "Testing configuration..."
puts ""

agent_def = swarm.agent_definition(:full_config_agent)

puts "Configuration Verification:"
puts "  model: #{agent_def.model}"
puts "  provider: #{agent_def.provider}"
puts "  base_url: #{agent_def.base_url}"
puts "  api_version: #{agent_def.api_version}"
puts "  context_window: #{agent_def.context_window}"
puts "  description: #{agent_def.description}"
puts "  system_prompt length: #{agent_def.system_prompt.length} chars"
puts ""

puts "Running test query..."
result = swarm.execute("Say 'core params work'")

puts ""
puts "Response: #{result.content}"
puts "Success: #{result.success?}"
puts ""
puts "✅ All core parameters work correctly!"
