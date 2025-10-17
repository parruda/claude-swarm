#!/usr/bin/env ruby
# frozen_string_literal: true

# Production Monitoring with Hooks - Advanced Level
#
# This example demonstrates production-ready patterns with the NEW architecture:
# - Structured logging (JSON format)
# - Metrics collection (Prometheus/StatsD compatible)
# - Error tracking and alerting
# - Performance monitoring
# - Audit trails
# - Cost tracking per user/tenant using agent_step
#
# NEW ARCHITECTURE: Usage tracking uses agent_step and agent_stop!
#
# Run: bundle exec ruby -Ilib lib/swarm_sdk/examples/hooks/03_production_monitoring.rb

require "swarm_sdk"
require "json"
require "logger"

puts "=" * 80
puts "PRODUCTION MONITORING EXAMPLE"
puts "=" * 80
puts ""

# Setup structured logging
@logger = Logger.new($stdout)
@logger.level = Logger::INFO
@logger.formatter = proc do |severity, datetime, _progname, msg|
  {
    timestamp: datetime.utc.iso8601,
    severity: severity,
    message: msg,
  }.to_json + "\n"
end

# Metrics collector (simulates StatsD/Prometheus)
class MetricsCollector
  def initialize
    @metrics = Hash.new { |h, k| h[k] = [] }
  end

  def increment(metric, value = 1, tags = {})
    @metrics[metric] << { value: value, tags: tags, timestamp: Time.now }
  end

  def timing(metric, duration_ms, tags = {})
    @metrics[metric] << { duration_ms: duration_ms, tags: tags, timestamp: Time.now }
  end

  def gauge(metric, value, tags = {})
    @metrics[metric] << { value: value, tags: tags, timestamp: Time.now }
  end

  def report
    @metrics.each do |metric, values|
      puts "\n#{metric}:"
      if metric.include?("timing")
        durations = values.map { |v| v[:duration_ms] }
        puts "  Count: #{durations.size}"
        puts "  Min: #{durations.min}ms"
        puts "  Max: #{durations.max}ms"
        puts "  Avg: #{(durations.sum / durations.size.to_f).round(2)}ms"
      else
        puts "  Count: #{values.size}"
        puts "  Total: #{values.map { |v| v[:value] }.sum}"
      end
    end
  end
end

@metrics = MetricsCollector.new

# Track operation timings
@operation_start_times = {}

# User/tenant context (for multi-tenant systems)
USER_ID = ENV["USER_ID"] || "user_123"
TENANT_ID = ENV["TENANT_ID"] || "tenant_abc"

# Cost limits per user
COST_LIMITS = {
  "user_123" => { daily: 10.0, per_request: 1.0 },
}.freeze

# Track costs per user
@user_costs = Hash.new { |h, k| h[k] = { daily: 0.0, current_request: 0.0 } }

swarm = SwarmSDK.build do
  name("Production Monitor")
  lead(:worker)

  # ============================================================================
  # 1. REQUEST TRACKING
  # ============================================================================

  hook(:swarm_start) do |context|
    request_id = SecureRandom.uuid

    @logger.info({
      event: "request_start",
      request_id: request_id,
      user_id: USER_ID,
      tenant_id: TENANT_ID,
      agent: context.agent_name,
      prompt_length: context.metadata[:prompt]&.length,
    })

    # Store request_id in metadata for other hooks
    context.metadata[:request_id] = request_id
    context.metadata[:request_start] = Time.now

    @metrics.increment("swarm.requests", 1, user_id: USER_ID, tenant_id: TENANT_ID)
  end

  hook(:swarm_stop) do |context|
    duration_ms = ((Time.now - context.metadata[:request_start]) * 1000).round(2)

    @logger.info({
      event: "request_complete",
      request_id: context.metadata[:request_id],
      user_id: USER_ID,
      tenant_id: TENANT_ID,
      duration_ms: duration_ms,
      success: context.metadata[:success],
      total_cost: context.metadata[:total_cost],
    })

    @metrics.timing("swarm.request_duration", duration_ms, user_id: USER_ID)
    @metrics.gauge("swarm.request_cost", context.metadata[:total_cost], user_id: USER_ID)
  end

  # ============================================================================
  # 2. TOOL MONITORING (NO USAGE HERE!)
  # ============================================================================

  hook(:pre_tool_use) do |context|
    @operation_start_times[context.tool_call.id] = Time.now

    @logger.info({
      event: "tool_start",
      tool: context.tool_name,
      tool_call_id: context.tool_call.id,
      agent: context.agent_name,
      user_id: USER_ID,
      parameters: context.tool_call.parameters.keys,
    })

    @metrics.increment("tools.invocations", 1, tool: context.tool_name, agent: context.agent_name)
  end

  hook(:post_tool_use) do |context|
    # Calculate tool execution time
    start_time = @operation_start_times[context.tool_result.tool_call_id]
    duration_ms = start_time ? ((Time.now - start_time) * 1000).round(2) : 0

    # NO USAGE DATA HERE! (moved to agent_step)
    log_data = {
      event: "tool_complete",
      tool: context.tool_name,
      tool_call_id: context.tool_result.tool_call_id,
      agent: context.agent_name,
      user_id: USER_ID,
      tenant_id: TENANT_ID,
      success: context.tool_result.success?,
      duration_ms: duration_ms,
    }

    # Log errors
    unless context.tool_result.success?
      log_data[:error] = context.tool_result.error
      @metrics.increment("tools.errors", 1, tool: context.tool_name)
    end

    @logger.info(log_data)
    @metrics.timing("tools.duration", duration_ms, tool: context.tool_name)

    # Cleanup
    @operation_start_times.delete(context.tool_result.tool_call_id)
  end

  # ============================================================================
  # 3. AGENT STEP MONITORING (USAGE IS HERE!)
  # ============================================================================

  # NEW: agent_step hook for usage tracking!
  hook(:agent_step) do |context|
    usage = context.metadata[:usage]

    if usage
      cost = usage[:total_cost]
      tool_calls_count = context.metadata[:tool_calls]&.size || 0

      @logger.info({
        event: "agent_step",
        agent: context.agent_name,
        user_id: USER_ID,
        tenant_id: TENANT_ID,
        model: context.metadata[:model],
        tokens_total: usage[:total_tokens],
        tokens_input: usage[:input_tokens],
        tokens_output: usage[:output_tokens],
        cost: cost,
        context_usage_percent: usage[:tokens_used_percentage],
        tool_calls_count: tool_calls_count,
      })

      # Track costs per user
      @user_costs[USER_ID][:daily] += cost
      @user_costs[USER_ID][:current_request] += cost

      # Check cost limits
      limits = COST_LIMITS[USER_ID]
      if limits
        if @user_costs[USER_ID][:current_request] > limits[:per_request]
          @logger.error({
            event: "cost_limit_exceeded",
            limit_type: "per_request",
            user_id: USER_ID,
            cost: @user_costs[USER_ID][:current_request],
            limit: limits[:per_request],
          })

          SwarmSDK::Hooks::Result.halt("Request cost limit exceeded: $#{limits[:per_request]}")
        end

        if @user_costs[USER_ID][:daily] > limits[:daily]
          @logger.error({
            event: "cost_limit_exceeded",
            limit_type: "daily",
            user_id: USER_ID,
            cost: @user_costs[USER_ID][:daily],
            limit: limits[:daily],
          })

          SwarmSDK::Hooks::Result.halt("Daily cost limit exceeded: $#{limits[:daily]}")
        end
      end

      # Metrics
      @metrics.gauge("agent.step_cost", cost, agent: context.agent_name, user_id: USER_ID)
      @metrics.gauge("agent.step_tokens", usage[:total_tokens], agent: context.agent_name)
      @metrics.increment("agent.steps", 1, agent: context.agent_name)
    end
  end

  # ============================================================================
  # 4. CONTEXT MONITORING
  # ============================================================================

  hook(:context_warning) do |context|
    threshold = context.metadata[:threshold]
    percentage = context.metadata[:percentage]

    @logger.warn({
      event: "context_warning",
      agent: context.agent_name,
      user_id: USER_ID,
      threshold: threshold,
      percentage: percentage,
      tokens_used: context.metadata[:tokens_used],
      tokens_remaining: context.metadata[:tokens_remaining],
    })

    @metrics.gauge("context.usage_percent", percentage, agent: context.agent_name)

    # Alert if critical
    if percentage > 95
      @logger.error({
        event: "context_critical",
        agent: context.agent_name,
        percentage: percentage,
        message: "Context window nearly full - execution may fail",
      })
    end
  end

  # ============================================================================
  # 5. AGENT LIFECYCLE
  # ============================================================================

  hook(:agent_stop) do |context|
    usage = context.metadata[:usage]

    @logger.info({
      event: "agent_complete",
      agent: context.agent_name,
      user_id: USER_ID,
      model: context.metadata[:model],
      finish_reason: context.metadata[:finish_reason],
      tokens_total: usage[:total_tokens],
      cost: usage[:total_cost],
      context_usage: usage[:tokens_used_percentage],
    })

    # Track final step cost
    if usage
      cost = usage[:total_cost]
      @user_costs[USER_ID][:daily] += cost
      @user_costs[USER_ID][:current_request] += cost
    end

    @metrics.increment("agent.completions", 1, agent: context.agent_name)
    @metrics.gauge("agent.final_cost", usage[:total_cost], agent: context.agent_name)
  end

  # ============================================================================
  # 6. ERROR TRACKING
  # ============================================================================

  # NOTE: In production, you'd integrate with Sentry, Rollbar, etc.
  # This is a simplified example.

  agent(:worker) do
    description("Worker agent with comprehensive monitoring")
    model("gpt-4o-mini")
    system_prompt("You are a helpful worker. Complete tasks efficiently.")
    tools(:Write)
  end
end

# Execute task
puts "\n--- Executing Monitored Task ---"
puts "User: #{USER_ID}"
puts "Tenant: #{TENANT_ID}"
puts ""

begin
  result = swarm.execute("Create a file called report.txt with a brief summary of monitoring best practices")

  puts "\n--- Execution Complete ---"
  puts "Success: #{result.success?}"
  puts "Cost: $#{format("%.6f", @user_costs[USER_ID][:current_request])}"
  puts ""

  # Show metrics report
  puts "\n--- Metrics Report ---"
  @metrics.report

  # Show user cost tracking
  puts "\n--- User Cost Tracking ---"
  @user_costs.each do |user_id, costs|
    puts "#{user_id}:"
    puts "  Current request: $#{format("%.6f", costs[:current_request])}"
    puts "  Daily total: $#{format("%.6f", costs[:daily])}"

    next unless (limits = COST_LIMITS[user_id])

    puts "  Limits:"
    puts "    Per request: $#{limits[:per_request]} (#{(costs[:current_request] / limits[:per_request] * 100).round}% used)"
    puts "    Daily: $#{limits[:daily]} (#{(costs[:daily] / limits[:daily] * 100).round}% used)"
  end
rescue => e
  @logger.error({
    event: "execution_error",
    user_id: USER_ID,
    error_class: e.class.name,
    error_message: e.message,
    backtrace: e.backtrace[0..5],
  })

  puts "\nError: #{e.message}"
end

puts "\n" + "=" * 80
puts "PRODUCTION PATTERNS DEMONSTRATED"
puts "=" * 80
puts <<~SUMMARY

  1. **Structured Logging**
     - JSON format for easy parsing
     - Rich context (user_id, tenant_id, request_id)
     - Event-based structure
     - Integration-ready (Elasticsearch, CloudWatch, etc.)

  2. **Metrics Collection**
     - Counters (requests, tool invocations, agent steps, errors)
     - Timings (request duration, tool execution time)
     - Gauges (costs, token usage, context percentage)
     - Tags for grouping (user, tenant, tool, agent)

  3. **Cost Management (NEW ARCHITECTURE!)**
     - Per-user cost tracking in agent_step hook
     - Daily and per-request limits
     - Automatic limit enforcement
     - Cost attribution (which user/tenant spent what)

  4. **Performance Monitoring**
     - Request duration tracking
     - Tool execution timing
     - Agent step tracking
     - Context usage monitoring

  5. **Error Tracking**
     - Tool failure logging
     - Context overflow warnings
     - Cost limit violations
     - Integration-ready for Sentry/Rollbar

  6. **Audit Trail**
     - Complete request lifecycle tracking
     - Tool parameter logging (keys only for security)
     - User/tenant attribution
     - Compliance-ready logging

  **KEY ARCHITECTURAL CHANGE:**
  - Usage tracking moved from post_tool_use to agent_step!
  - post_tool_use: Tracks tool execution (duration, success/failure)
  - agent_step: Tracks LLM usage (tokens, costs)
  - One agent_step may trigger multiple tool calls
  - Usage reflects the cost of the LLM response, not individual tools

  **Integration Points:**
  - Logs → Elasticsearch, CloudWatch, Datadog
  - Metrics → Prometheus, StatsD, Datadog
  - Errors → Sentry, Rollbar, Bugsnag
  - Costs → Internal billing systems

  **Production Considerations:**
  - Implement log sampling for high-volume systems
  - Use async metrics shipping (avoid blocking hooks)
  - Set up alerting on critical thresholds
  - Configure log retention policies
  - Implement PII scrubbing in logs

SUMMARY

puts "=" * 80
