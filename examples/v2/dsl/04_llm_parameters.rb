#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 4: LLM Parameters
#
# Tests: parameters (temperature, max_tokens, reasoning), timeout
#
# Run: VAULT_TOKEN=xxx bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/04_llm_parameters.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"

ENV["OPENAI_API_KEY"] = "test-key"

swarm = SwarmSDK.build do
  name("LLM Parameters Test")
  lead(:configured_agent)

  agent(:configured_agent) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You test LLM parameters. Be concise.")
    description("Agent with custom LLM parameters")
    tools(:Read)

    # LLM parameters hash
    parameters(
      temperature: 0.3,
      max_tokens: 100,
      reasoning: "low",
    )

    # HTTP timeout
    timeout(60)
  end
end

puts "✅ Swarm with LLM parameters built!"
puts ""

agent_def = swarm.agent_definition(:configured_agent)

puts "Parameter Verification:"
puts "  parameters: #{agent_def.parameters.inspect}"
puts "  timeout: #{agent_def.timeout}"
puts ""

puts "Running test query with configured parameters..."
result = swarm.execute("Count to 3")

puts ""
puts "Response: #{result.content}"
puts "Success: #{result.success?}"
puts ""
puts "✅ LLM parameters and timeout work!"
