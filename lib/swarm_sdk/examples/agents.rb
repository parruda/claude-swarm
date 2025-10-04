# frozen_string_literal: true

require "swarm_sdk"

# Create the swarm with clearer concurrency naming
swarm = SwarmSDK::Swarm.new(
  name: "Multi-Model Development Team",
  global_concurrency: 50, # Max 50 concurrent LLM calls across entire swarm
  default_local_concurrency: 10, # Each agent can make 10 concurrent tool calls by default
)

# Parent agent - GPT-5-mini
swarm.add_agent(
  name: :architect,
  description: "Lead architect coordinating the team using GPT-5",
  model: "gpt-5-mini",
  provider: "openai",
  base_url: "http://proxy-shopify-ai.local.shop.dev/v1",
  system_prompt: "You are the lead architect. Coordinate work between the frontend and backend teams. Delegate tasks appropriately based on their expertise.",
  delegates_to: [:frontend_dev, :backend_dev],
  directories: ["."],
  timeout: 300, # 5 minutes (default) - increase for reasoning models
)

# Delegate 1 - Gemini
swarm.add_agent(
  name: :frontend_dev,
  description: "Frontend developer using Sonnet 4.5",
  model: "anthropic:claude-sonnet-4-5",
  provider: "openai",
  base_url: "http://proxy-shopify-ai.local.shop.dev/v1",
  system_prompt: "You are a frontend developer specializing in React and UI/UX. Build clean, maintainable frontend code with great user experience.",
  directories: ["./frontend"],
)

# Delegate 2 - Claude
swarm.add_agent(
  name: :backend_dev,
  description: "Backend developer using Claude Sonnet 4.5",
  model: "anthropic:claude-sonnet-4-5",
  provider: "openai",
  base_url: "http://proxy-shopify-ai.local.shop.dev/v1",
  system_prompt: "You are a backend developer specializing in APIs and databases. Build scalable backend architecture with clean code practices.",
  directories: ["./backend"],
)

swarm.lead = :architect

# Stream log entries as the swarm executes
result = swarm.execute("Build a user authentication system with login UI and API endpoints") do |log_entry|
  # Format log entry based on type
  case log_entry[:type]
  when "llm_request"
    puts "[#{log_entry[:agent]}] Starting LLM call (#{log_entry[:model]}) with #{log_entry[:message_count]} messages"
  when "llm_response"
    tokens = log_entry[:usage][:total_tokens]
    cost = log_entry[:usage][:total_cost]
    puts "[#{log_entry[:agent]}] LLM response: #{tokens} tokens ($#{format("%.6f", cost)})"
    if log_entry[:content]
      puts "  Content: #{log_entry[:content][0..100]}..." if log_entry[:content].length > 100
      puts "  Content: #{log_entry[:content]}" if log_entry[:content].length <= 100
    end
  when "tool_call"
    puts "[#{log_entry[:agent]}] Tool call: #{log_entry[:tool]}"
  when "tool_result"
    puts "[#{log_entry[:agent]}] Tool result received"
  end
end

# Print final result
puts "\n=== Final Result ==="
puts result.content
