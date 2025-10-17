#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage Tracking with Hooks - Intermediate Level
#
# This example demonstrates usage tracking with the NEW agent_step architecture:
# - Access token usage and costs in agent_step hooks
# - Track costs per agent response
# - Implement budget limits
# - Monitor context window usage
# - Generate cost reports
#
# NEW ARCHITECTURE: Usage is in agent_step and agent_stop, NOT post_tool_use!
#
# Run: bundle exec ruby -Ilib lib/swarm_sdk/examples/hooks/02_usage_tracking.rb

require "swarm_sdk"

puts "=" * 80
puts "USAGE TRACKING WITH HOOKS"
puts "=" * 80
puts ""

# Track costs across all operations
@total_cost = 0.0
@step_costs = []
@step_count = 0

# Budget limit (in dollars)
BUDGET_LIMIT = 0.10 # 10 cents

swarm = SwarmSDK.build do
  name("Cost Tracking Demo")
  lead(:analyst)

  # NEW ARCHITECTURE: Usage tracking in agent_step!
  # agent_step fires when the LLM responds with tool calls
  hook(:agent_step) do |context|
    # Access usage metadata (NEW LOCATION!)
    usage = context.metadata[:usage]

    if usage
      @step_count += 1
      cost = usage[:total_cost]
      input_tokens = usage[:input_tokens]
      output_tokens = usage[:output_tokens]

      # Track costs
      @total_cost += cost
      @step_costs << {
        step: @step_count,
        cost: cost,
        tokens: usage[:total_tokens],
        tool_calls: context.metadata[:tool_calls]&.size || 0,
      }

      # Log usage information
      puts "\n💰 Agent Step #{@step_count}:"
      puts "   Tokens: #{input_tokens} in + #{output_tokens} out = #{usage[:total_tokens]} total"
      puts "   Cost: $#{format("%.6f", cost)}"
      puts "   Running total: $#{format("%.6f", @total_cost)}"
      puts "   Tool calls: #{@step_costs.last[:tool_calls]}"

      # Check context usage
      if usage[:tokens_used_percentage]
        puts "   Context: #{usage[:tokens_used_percentage]} (#{usage[:tokens_remaining]} tokens remaining)"
      end

      # Warn if approaching budget limit
      if @total_cost > BUDGET_LIMIT * 0.8
        puts "   ⚠️  WARNING: Approaching budget limit (#{(@total_cost / BUDGET_LIMIT * 100).round}%)"
      end

      # HALT if budget exceeded
      if @total_cost > BUDGET_LIMIT
        puts "   🛑 BUDGET EXCEEDED!"
        SwarmSDK::Hooks::Result.halt("Budget limit of $#{BUDGET_LIMIT} exceeded")
      end
    end
  end

  # Monitor context warnings
  hook(:context_warning) do |context|
    puts "\n⚠️  Context Warning:"
    puts "   Threshold: #{context.metadata[:threshold]}%"
    puts "   Current usage: #{context.metadata[:percentage].round(1)}%"
    puts "   Tokens remaining: #{context.metadata[:tokens_remaining]}"
  end

  # agent_stop fires when the LLM gives final response (no more tool calls)
  hook(:agent_stop) do |context|
    usage = context.metadata[:usage]

    puts "\n🏁 Agent Completed:"
    puts "   Model: #{context.metadata[:model]}"
    puts "   Finish reason: #{context.metadata[:finish_reason]}"

    if usage
      @step_count += 1
      cost = usage[:total_cost]
      @total_cost += cost

      puts "   Final step tokens: #{usage[:total_tokens]}"
      puts "   Final step cost: $#{format("%.6f", cost)}"
      puts "   Total cost: $#{format("%.6f", @total_cost)}"
      puts "   Context usage: #{usage[:tokens_used_percentage]}"
    end
  end

  agent(:analyst) do
    description("Data analyst that processes files")
    model("gpt-4o-mini") # Cheaper model for demo
    system_prompt(<<~PROMPT)
      You are a data analyst. Analyze files and generate reports.
      Use the available tools to read files and create summaries.
    PROMPT

    tools(:Write)
  end
end

puts "Budget limit: $#{BUDGET_LIMIT}"
puts ""

# Execute a task
puts "\n--- Running Task ---"
begin
  result = swarm.execute(<<~TASK)
    Create a short analysis report about Ruby programming.
    Write it to analysis.txt.

    Include:
    1. Brief overview of Ruby
    2. Key features
    3. Common use cases
  TASK

  puts "\n--- Task Complete ---"
  puts "Success: #{result.success?}"
  puts "Total cost: $#{format("%.6f", @total_cost)}"
  puts "Total steps: #{@step_count}"

  # Generate cost breakdown
  puts "\n--- Cost Breakdown by Step ---"
  @step_costs.each do |step|
    puts "Step #{step[:step]}:"
    puts "  Cost: $#{format("%.6f", step[:cost])}"
    puts "  Tokens: #{step[:tokens]}"
    puts "  Tool calls: #{step[:tool_calls]}"
  end
rescue => e
  puts "\nError: #{e.message}"
end

puts "\n" + "=" * 80
puts "KEY FEATURES DEMONSTRATED"
puts "=" * 80
puts <<~SUMMARY

  1. **NEW ARCHITECTURE: Usage in agent_step hook**
     - agent_step fires when LLM responds with tool calls
     - agent_stop fires when LLM gives final response
     - Usage is NO LONGER in post_tool_use!

  2. **Usage Data Structure**
     - context.metadata[:usage] contains:
       * input_tokens, output_tokens, total_tokens
       * input_cost, output_cost, total_cost
       * cumulative_input_tokens, cumulative_output_tokens
       * context_limit, tokens_used_percentage, tokens_remaining

  3. **Cost Tracking**
     - Track total costs across all agent steps
     - Break down costs by step
     - Each LLM response is one step

  4. **Budget Limits**
     - Implement spending limits
     - Warn when approaching limit
     - Halt execution when exceeded

  5. **Context Monitoring**
     - Monitor token usage as percentage
     - Track remaining context window
     - Receive warnings at thresholds (80%, 90%, etc.)

  **KEY DIFFERENCE FROM OLD ARCHITECTURE:**
  - OLD: Usage in post_tool_use (one per tool)
  - NEW: Usage in agent_step (one per LLM response)
  - An agent_step may include multiple tool calls
  - Usage reflects the cost of the LLM response that generated those tool calls

  **Example Flow:**
  1. User prompt → LLM responds with tool calls → agent_step hook (with usage)
  2. Tools execute → post_tool_use hooks (NO usage)
  3. Tool results sent to LLM → LLM responds with more tool calls → agent_step (with usage)
  4. LLM gives final answer → agent_stop hook (with usage)

SUMMARY

puts "=" * 80
