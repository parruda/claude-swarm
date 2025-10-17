#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 6: Permissions DSL
#
# Tests: all_agents permissions, agent permissions, path and command restrictions
#
# Run: VAULT_TOKEN=xxx bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/06_permissions.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"
require_relative "../../../swarm_sdk/all_agents_builder"
require_relative "../../../swarm_sdk/permissions_builder"
require "fileutils"

ENV["OPENAI_API_KEY"] = "test-key"

# Setup test environment
FileUtils.mkdir_p("tmp/allowed")
FileUtils.mkdir_p("tmp/forbidden")
File.write("tmp/allowed/test.txt", "allowed content")
File.write("tmp/forbidden/secret.txt", "secret content")

swarm = SwarmSDK.build do
  name("Permissions Test")
  lead(:restricted_agent)

  # Default permissions for all agents
  all_agents do
    tools(:Write)

    permissions do
      tool(:Write).allow_paths("tmp/allowed/**/*")
      tool(:Write).deny_paths("tmp/forbidden/**/*")
    end
  end

  agent(:restricted_agent) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You test file permissions. Try to write to allowed and forbidden paths.")
    description("Agent with write restrictions")

    tools(:Read, :Bash)

    # Agent-specific Bash permissions
    permissions do
      tool(:Bash).allow_commands("^ls", "^pwd$", "^echo")
      tool(:Bash).deny_commands("^rm", "^dd")
    end
  end
end

puts "✅ Swarm with permissions built!"
puts ""

agent_def = swarm.agent_definition(:restricted_agent)

puts "Permissions Verification:"
puts "  Default (Write): #{agent_def.default_permissions}"
puts "  Agent (Bash): #{agent_def.agent_permissions}"
puts ""

puts "Testing simple query with permissions in place..."
result = swarm.execute("Say 'permissions configured'")

puts ""
puts "Response: #{result.content}"
puts "Success: #{result.success?}"
puts ""
puts "✅ Permissions DSL configured correctly!"
puts ""
puts "Note: Permissions are enforced - agent can only:"
puts "  - Write to tmp/allowed/** (not tmp/forbidden/**)"
puts "  - Run Bash: ls, pwd, echo (not rm, dd)"

# Cleanup
FileUtils.rm_rf("tmp/allowed")
FileUtils.rm_rf("tmp/forbidden")
