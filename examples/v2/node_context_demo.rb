#!/usr/bin/env ruby
# frozen_string_literal: true

# NodeContext Demo
#
# This example demonstrates the NodeContext capabilities:
# - Access original_prompt from any node
# - Access all previous node results
# - Convenience accessors (ctx.content)
#
# Run: ruby examples/node_context_demo.rb

require_relative "../lib/swarm_sdk"

swarm = SwarmSDK.build do
  name("NodeContext Demo")

  # Define agents
  agent(:planner) do
    model("claude-sonnet-4-5")
    provider("openai")
    description("Planning agent")
    system_prompt("Create a brief plan.")
    tools(include_default: false)
  end

  agent(:implementer) do
    model("claude-sonnet-4-5")
    provider("openai")
    description("Implementation agent")
    system_prompt("Implement the plan.")
    tools(include_default: false)
  end

  agent(:reviewer) do
    model("claude-sonnet-4-5")
    provider("openai")
    description("Review agent")
    system_prompt("Review the work.")
    tools(include_default: false)
  end

  # Node 1: Planning
  node(:planning) do
    agent(:planner)

    output do |ctx|
      puts "\n[planning output transformer]"
      puts "  ctx.content: #{ctx.content[0..60]}..."
      puts "  ctx.original_prompt: #{ctx.original_prompt}"
      puts "  ctx.node_name: #{ctx.node_name}"

      "PLAN: #{ctx.content}"
    end
  end

  # Node 2: Implementation
  node(:implementation) do
    agent(:implementer)
    depends_on(:planning)

    input do |ctx|
      puts "\n[implementation input transformer]"
      puts "  ctx.content (transformed from planning): #{ctx.content[0..60]}..."
      puts "  ctx.original_prompt: #{ctx.original_prompt}"
      puts "  ctx.all_results[:planning].content: #{ctx.all_results[:planning].content[0..40]}..."
      puts "  ctx.node_name: #{ctx.node_name}"
      puts "  ctx.dependencies: #{ctx.dependencies.inspect}"

      ctx.content
    end

    output do |ctx|
      "IMPLEMENTATION: #{ctx.content}"
    end
  end

  # Node 3: Review - demonstrate accessing ALL previous results
  node(:review) do
    agent(:reviewer) # No delegation, just solo review

    depends_on(:implementation)

    input do |ctx|
      puts "\n[review input transformer]"
      puts "  ctx.original_prompt: #{ctx.original_prompt}"
      puts "  ctx.all_results.keys: #{ctx.all_results.keys.inspect}"

      # Access specific previous nodes
      plan = ctx.all_results[:planning].content
      impl = ctx.all_results[:implementation].content

      puts "  Planning node result: #{plan[0..40]}..."
      puts "  Implementation node result: #{impl[0..40]}..."

      <<~PROMPT
        Review this work:

        ORIGINAL REQUEST: #{ctx.original_prompt}

        PLAN:
        #{plan}

        IMPLEMENTATION:
        #{impl}

        Provide feedback.
      PROMPT
    end
  end

  start_node(:planning)
end

puts "=" * 80
puts "NodeContext Demo"
puts "=" * 80
puts "\nExecuting workflow with NodeContext...\n"

result = swarm.execute("Build a todo API")

puts "\n"
puts "=" * 80
puts "Final Result:"
puts "=" * 80
puts result.content
puts "=" * 80
