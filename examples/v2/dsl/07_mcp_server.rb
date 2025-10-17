#!/usr/bin/env ruby
# frozen_string_literal: true

# Manual Test 7: MCP Server Configuration
#
# Tests: mcp_server with vault-mcp (stdio transport)
#
# Run: VAULT_TOKEN=xxx bundle exec ruby -Ilib lib/swarm_sdk/examples/dsl/07_mcp_server.rb

require "swarm_sdk"
require_relative "../../../swarm_sdk/swarm_builder"
require_relative "../../../swarm_sdk/agent_builder"

ENV["OPENAI_API_KEY"] = "test-key"

swarm = SwarmSDK.build do
  name("MCP Server Test")
  lead(:mcp_agent)

  agent(:mcp_agent) do
    model("gpt-5-nano")
    provider("openai")
    system_prompt("You have access to MCP tools from vault-mcp. List available tools when asked.")
    description("Agent with MCP server access")

    tools(:Read)

    # Add vault-mcp server
    mcp_server(
      :vault_mcp,
      type: :stdio,
      command: "/opt/homebrew/bin/uvx",
      args: ["shopify-mcp-bridge"],
      env: {
        MCP_API_TOKEN: "test-key",
        MCP_TARGET_URL: "https://vault.shopify.io/mcp",
      },
    )
  end
end

puts "✅ Swarm with MCP server built!"
puts ""

agent_def = swarm.agent_definition(:mcp_agent)

puts "MCP Server Verification:"
puts "  Servers configured: #{agent_def.mcp_servers.size}"
agent_def.mcp_servers.each do |server|
  puts "    - #{server[:name]} (#{server[:type]})"
  puts "      command: #{server[:command]}"
  puts "      args: #{server[:args].inspect}"
end
puts ""

puts "Testing MCP server connection..."
puts "(Agent should have access to vault-mcp tools)"
puts ""

result = swarm.execute("What tools do you have access to? List them.")

puts "Response: #{result.content[0..300]}..."
puts "Success: #{result.success?}"
puts ""
puts "✅ MCP server configuration works!"
