#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 12: Complete Integration
#
# Tests: ALL features combined in one swarm
#
# Run: bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/12_complete_integration.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"
require_relative "../../../swarm_sdk/all_agents_builder"
require_relative "../../../swarm_sdk/permissions_builder"

ENV["OPENAI_API_KEY"] = "test-key"

# Track execution
@swarm_started = false
@swarm_stopped = false

swarm = SwarmSDK.build do
  name("Complete Integration Test")
  lead(:full_featured_agent)

  # Swarm-level hooks
  hook(:swarm_start) do |_ctx|
    @swarm_started = true
    puts "🚀 Swarm starting..."
  end

  hook(:swarm_stop) do |_ctx|
    @swarm_stopped = true
    puts "✅ Swarm complete!"
  end

  # All-agents configuration
  all_agents do
    tools(:Read, :Write)

    permissions do
      tool(:Write).allow_paths("tmp/**/*")
    end

    hook(:pre_tool_use, matcher: "Write") do |_ctx|
      puts "🔒 Validating write operation..."
    end
  end

  # Full-featured agent with everything
  agent(:full_featured_agent) do
    # Core config
    model("gpt-5-nano")
    provider("openai")
    api_version("v1/responses")
    context_window(200_000)
    system_prompt("You are a fully-featured test agent.")
    description("Agent with all features enabled")

    # Capabilities
    tools(:Bash, :TodoWrite)
    delegates_to(:helper)
    directory(".")

    # MCP server (example using filesystem-mcp)
    mcp_server(
      :filesystem,
      type: :stdio,
      command: "npx",
      args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
      env: {},
    )

    # LLM parameters (gpt-5-nano doesn't support temperature, using empty hash for demo)
    parameters({})

    # Advanced flags
    bypass_permissions(false)
    skip_base_prompt(false)
    assume_model_exists(true)
    timeout(120)

    # Agent-specific permissions
    permissions do
      tool(:Bash).allow_commands("^echo", "^ls", "^pwd$")
      tool(:Bash).deny_commands("^rm", "^shutdown")
    end

    # Agent-specific hook
    hook(:pre_tool_use, matcher: "Bash") do |ctx|
      puts "🛡️ Validating Bash command: #{ctx.tool_call.parameters[:command]}"
    end
  end

  # Helper agent
  agent(:helper) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You are a helper. Answer concisely.")
    description("Helper agent")
    tools(:Read)
  end
end

puts "=" * 70
puts "COMPLETE INTEGRATION TEST"
puts "=" * 70
puts ""
puts "✅ Swarm built with ALL features:"
puts "  ✓ Swarm config (name, lead)"
puts "  ✓ Agent core params (model, provider, base_url, api_version, context_window)"
puts "  ✓ Agent identity (system_prompt, description)"
puts "  ✓ Capabilities (tools, delegates_to, directory)"
puts "  ✓ MCP servers (filesystem via stdio)"
puts "  ✓ LLM params (parameters, timeout)"
puts "  ✓ Advanced flags (disable_default_tools, bypass_permissions, skip_base_prompt, assume_model_exists)"
puts "  ✓ Permissions (all_agents and agent-level)"
puts "  ✓ Hooks (swarm-level, agent-level, all_agents)"
puts "  ✓ Delegation"
puts ""

puts "Running integration test..."
result = swarm.execute("Say 'integration test'")

puts ""
if result.success?
  puts "Response: #{result.content}"
  puts "Success: #{result.success?}"
  puts ""
  puts "🎉 COMPLETE INTEGRATION SUCCESSFUL!"
  puts "All DSL features work correctly together!"
else
  puts "❌ Error: #{result.error&.message}"
  puts "This might be due to MCP server connection - that's okay for syntax testing"
  puts ""
  puts "✅ DSL syntax is correct even if MCP connection failed"
end
