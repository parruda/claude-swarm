# frozen_string_literal: true

module ClaudeSwarm
  module SessionCostCalculator
    extend self

    # Model pricing in dollars per million tokens
    MODEL_PRICING = {
      opus: {
        input: 15.0,
        output: 75.0,
        cache_write: 18.75,
        cache_read: 1.50,
      },
      sonnet: {
        input: 3.0,
        output: 15.0,
        cache_write: 3.75,
        cache_read: 0.30,
      },
      haiku: {
        input: 0.80,
        output: 4.0,
        cache_write: 1.0,
        cache_read: 0.08,
      },
    }.freeze

    # Determine model type from model name
    def model_type_from_name(model_name)
      return unless model_name

      model_name_lower = model_name.downcase
      if model_name_lower.include?("opus")
        :opus
      elsif model_name_lower.include?("sonnet")
        :sonnet
      elsif model_name_lower.include?("haiku")
        :haiku
      end
    end

    # Calculate cost from token usage
    def calculate_token_cost(usage, model_name)
      model_type = model_type_from_name(model_name)
      return 0.0 unless model_type && usage

      pricing = MODEL_PRICING[model_type]
      return 0.0 unless pricing

      cost = 0.0

      # Regular input tokens
      if usage["input_tokens"]
        cost += (usage["input_tokens"] / 1_000_000.0) * pricing[:input]
      end

      # Output tokens
      if usage["output_tokens"]
        cost += (usage["output_tokens"] / 1_000_000.0) * pricing[:output]
      end

      # Cache creation tokens (write)
      if usage["cache_creation_input_tokens"]
        cost += (usage["cache_creation_input_tokens"] / 1_000_000.0) * pricing[:cache_write]
      end

      # Cache read tokens
      if usage["cache_read_input_tokens"]
        cost += (usage["cache_read_input_tokens"] / 1_000_000.0) * pricing[:cache_read]
      end

      cost
    end

    # Calculate total cost from session log file
    # Returns a hash with:
    # - total_cost: Total cost in USD (sum of cost_usd for instances, token costs for main)
    # - instances_with_cost: Set of instance names that have cost data
    def calculate_total_cost(session_log_path)
      return { total_cost: 0.0, instances_with_cost: Set.new } unless File.exist?(session_log_path)

      # Track costs per instance - simple sum of cost_usd
      instance_costs = {}
      instances_with_cost = Set.new
      main_instance_cost = 0.0

      File.foreach(session_log_path) do |line|
        data = JsonHandler.parse(line)
        next if data == line # Skip unparseable lines

        instance_name = data["instance"]
        instance_id = data["instance_id"]

        # Handle main instance token-based costs
        if instance_id == "main" && data.dig("event", "type") == "assistant"
          usage = data.dig("event", "message", "usage")
          model = data.dig("event", "message", "model")
          if usage && model
            token_cost = calculate_token_cost(usage, model)
            main_instance_cost += token_cost
            instances_with_cost << instance_name if token_cost > 0
          end
        # Handle other instances with cost_usd (non-cumulative)
        elsif instance_id != "main" && data.dig("event", "type") == "result"
          # Use cost_usd (non-cumulative) instead of total_cost_usd (cumulative)
          if (cost = data.dig("event", "cost_usd"))
            instances_with_cost << instance_name
            instance_costs[instance_name] ||= 0.0
            instance_costs[instance_name] += cost
          end
        end
      end

      # Calculate total: sum of all instance costs + main instance token costs
      other_instances_cost = instance_costs.values.sum
      total_cost = other_instances_cost + main_instance_cost

      {
        total_cost: total_cost,
        instances_with_cost: instances_with_cost,
      }
    end

    # Calculate simple total cost (for backward compatibility)
    def calculate_simple_total(session_log_path)
      calculate_total_cost(session_log_path)[:total_cost]
    end

    # Parse instance hierarchy with costs from session log
    # Returns a hash of instances with their cost data and relationships
    def parse_instance_hierarchy(session_log_path)
      instances = {}
      # Track main instance token costs
      main_instance_costs = {}

      return instances unless File.exist?(session_log_path)

      File.foreach(session_log_path) do |line|
        data = JsonHandler.parse(line)
        next if data == line # Skip unparseable lines

        instance_name = data["instance"]
        instance_id = data["instance_id"]
        calling_instance = data["calling_instance"]

        # Initialize instance data
        instances[instance_name] ||= {
          name: instance_name,
          id: instance_id,
          cost: 0.0,
          calls: 0,
          called_by: Set.new,
          calls_to: Set.new,
          has_cost_data: false,
        }

        # Track relationships
        if calling_instance && calling_instance != instance_name
          instances[instance_name][:called_by] << calling_instance

          instances[calling_instance] ||= {
            name: calling_instance,
            id: data["calling_instance_id"],
            cost: 0.0,
            calls: 0,
            called_by: Set.new,
            calls_to: Set.new,
            has_cost_data: false,
          }
          instances[calling_instance][:calls_to] << instance_name
        end

        # Handle main instance token-based costs
        if instance_id == "main" && data.dig("event", "type") == "assistant"
          usage = data.dig("event", "message", "usage")
          model = data.dig("event", "message", "model")
          if usage && model
            token_cost = calculate_token_cost(usage, model)
            if token_cost > 0
              main_instance_costs[instance_name] ||= 0.0
              main_instance_costs[instance_name] += token_cost
              instances[instance_name][:has_cost_data] = true
              instances[instance_name][:calls] += 1
            end
          end
        # Track costs and calls for non-main instances using cost_usd
        elsif data.dig("event", "type") == "result" && instance_id != "main"
          instances[instance_name][:calls] += 1
          # Use cost_usd (non-cumulative) instead of total_cost_usd
          if (cost = data.dig("event", "cost_usd"))
            instances[instance_name][:cost] += cost
            instances[instance_name][:has_cost_data] = true
          end
        end
      end

      # Set main instance costs (replace, don't add)
      main_instance_costs.each do |name, cost|
        if instances[name]
          # For main instances, use ONLY token costs, not cumulative costs
          instances[name][:cost] = cost
        end
      end

      instances
    end
  end
end
