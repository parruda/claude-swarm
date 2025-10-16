#!/usr/bin/env ruby
# frozen_string_literal: true

# Node-Based Workflow Example
#
# This example demonstrates how to use nodes to create multi-stage workflows
# where different teams of agents collaborate in sequence.
#
# Features demonstrated:
# - NodeContext for accessing original_prompt and all_results
# - Multi-node workflows with delegation
# - Input/output transformers with full context access
#
# Run: ruby examples/node_workflow.rb

require_relative "../lib/swarm_sdk"

swarm = SwarmSDK.build do
  name("Haiku Workflow")

  # Define all agents globally
  agent(:planner) do
    model("claude-sonnet-4-5")
    description("Planning agent who breaks down tasks into smaller subtasks")
    provider("openai")
    system_prompt(<<~PROMPT)
      Your job is to break down tasks into smaller subtasks. Extract the intent of the user's prompt and break it down into smaller subtasks.
      Return a list of subtasks.
    PROMPT
    tools(include_default: false)
  end

  agent(:implementer) do
    model("claude-sonnet-4-5")
    description("Execution agent who executes the subtasks given to them")
    provider("openai")
    system_prompt(<<~PROMPT)
      Your job is to execute the subtasks given to you.
    PROMPT
    tools(include_default: false)
  end

  agent(:verifier) do
    model("claude-sonnet-4-5")
    description("Verifier agent who verifies the implementation")
    provider("openai")
    system_prompt(<<~PROMPT)
      Your job is to verify work given to you and return a summary of your findings
    PROMPT
    tools(include_default: false)
  end

  # Stage 1: Planning
  node(:planning) do
    # Input transformer - ctx.content is the initial prompt
    input do |ctx|
      <<~PROMPT
        Please break down the following prompt into smaller subtasks:

        #{ctx.content}
      PROMPT
    end

    agent(:planner)

    # Output transformer - ctx has access to original prompt and results
    output do |ctx|
      <<~PROMPT
        Here are the subtasks:

        #{ctx.content}

        Please implement these subtasks.
      PROMPT
    end
  end

  # Stage 2: Implementation
  node(:implementation) do
    # verifier is auto-added (mentioned in delegates_to)
    agent(:implementer).delegates_to(:verifier)

    depends_on(:planning)

    # Demonstrate NodeContext in input transformer
    input do |ctx|
      puts "\n[Node: implementation]"
      puts "  Original prompt: '#{ctx.original_prompt}'"
      puts "  Planning result: '#{ctx.all_results[:planning].content[0..60]}...'"
      puts "  Transformed input: '#{ctx.content[0..60]}...'\n"

      ctx.content # Use transformed content from planning output
    end

    # Transform output for review stage
    output do |ctx|
      <<~PROMPT
        Here is the implementation:

        #{ctx.content}

        Please review this implementation against the original plan.
      PROMPT
    end
  end

  # Stage 3: Review
  node(:review) do
    agent(:verifier)

    depends_on(:implementation)

    # Demonstrate full NodeContext capabilities - access ALL previous results
    input do |ctx|
      # Access original prompt
      original = ctx.original_prompt

      # Access specific previous node results via all_results
      plan = ctx.all_results[:planning].content
      implementation = ctx.all_results[:implementation].content

      # Current (transformed) content from implementation output
      transformed = ctx.content

      puts "\n[Node: review]"
      puts "  Accessing via NodeContext:"
      puts "    - Original prompt: '#{original}'"
      puts "    - Planning result: '#{plan[0..50]}...'"
      puts "    - Implementation result: '#{implementation[0..50]}...'"
      puts "    - Transformed input: '#{transformed[0..50]}...'\n"

      <<~PROMPT
        Review the implementation against the original plan:

        ORIGINAL REQUEST: #{original}

        PLAN:
        #{plan}

        IMPLEMENTATION:
        #{implementation}

        Provide feedback on whether this follows the plan and suggest improvements.
      PROMPT
    end
  end

  start_node(:planning)
end

puts "=" * 80
puts "Node-Based Workflow Example"
puts "=" * 80
puts
puts "This swarm has 3 stages:"
puts "1. Planning - Break down the task"
puts "2. Implementation - Execute the subtasks"
puts "3. Review - Verify the work"
puts
puts "=" * 80
puts

# Execute the workflow
result = swarm.execute("Write a haiku about the weather") do |log|
  puts log.to_json
end

puts "\n"
puts "=" * 80
puts "Final Result:"
puts "=" * 80
puts result.content
puts "=" * 80
