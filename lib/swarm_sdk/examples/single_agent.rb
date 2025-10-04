# frozen_string_literal: true

require "swarm_sdk"

# Create a swarm with a single agent using Claude Sonnet 4.5 through an OpenAI-compatible proxy
swarm = SwarmSDK::Swarm.new(
  name: "Single Agent Example",
  global_concurrency: 50,
  default_local_concurrency: 10,
)

# Add a single agent using Claude through a proxy
swarm.add_agent(
  name: :assistant,
  description: "AI assistant using Claude Sonnet 4.5",
  model: "anthropic:claude-sonnet-4-5",
  provider: "openai", # OpenAI-compatible proxy
  base_url: "http://proxy-shopify-ai.local.shop.dev/v1",
  system_prompt: "You are a helpful AI assistant. Provide clear, concise, and accurate responses.",
  directories: ["."],
  timeout: 300, # 5 minutes
  parameters: {
    temperature: 0.7,
    max_tokens: 4000,
  },
)

swarm.lead = :assistant

# Execute a task with streaming logs
result = swarm.execute("What are the key principles of good software design?") do |log_entry|
  case log_entry[:type]
  when "llm_request"
    puts "[#{log_entry[:agent]}] 🚀 Starting request to #{log_entry[:model]}"
  when "llm_response"
    tokens = log_entry[:usage][:total_tokens]
    cost = log_entry[:usage][:total_cost]
    puts "[#{log_entry[:agent]}] ✅ Response: #{tokens} tokens ($#{format("%.6f", cost)})"
  end
end

# Print the result
puts "\n" + "=" * 80
if result.error
  puts "❌ Error occurred:"
  puts "=" * 80
  puts result.error.class.name
  puts result.error.message
  puts result.error.backtrace.first(10).join("\n") if result.error.backtrace
else
  puts "✅ Response:"
  puts "=" * 80
  puts result.content
end
puts "=" * 80
puts "\n📊 Duration: #{result.duration.round(2)}s"
