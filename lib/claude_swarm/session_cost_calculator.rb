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
    # - total_cost: Total cost in USD (handles session resets and main instance token costs)
    # - instances_with_cost: Set of instance names that have cost data
    def calculate_total_cost(session_log_path)
      return { total_cost: 0.0, instances_with_cost: Set.new } unless File.exist?(session_log_path)

      # Track costs per instance, handling session resets
      instance_costs = {}
      instances_with_cost = Set.new
      main_instance_cost = 0.0

      File.foreach(session_log_path) do |line|
        data = JSON.parse(line)
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
        # Handle other instances with cumulative costs
        elsif data.dig("event", "type") == "result" && (cost = data.dig("event", "total_cost_usd"))
          instances_with_cost << instance_name

          # Initialize tracking for this instance if needed
          instance_costs[instance_name] ||= {
            accumulated: 0.0,  # Total accumulated from previous sessions
            last_seen: 0.0,    # Last cumulative value seen
          }

          # Check if session was reset (cost went down)
          if cost < instance_costs[instance_name][:last_seen]
            # Session was reset - add the previous session's total to accumulated
            instance_costs[instance_name][:accumulated] += instance_costs[instance_name][:last_seen]
          end

          # Update last seen cost
          instance_costs[instance_name][:last_seen] = cost
        end
      rescue JSON::ParserError
        next
      end

      # Calculate total: accumulated + current cumulative for each instance + main instance token costs
      other_instances_cost = instance_costs.values.sum { |costs| costs[:accumulated] + costs[:last_seen] }
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
      # Track session resets per instance
      cost_tracking = {}
      # Track main instance token costs
      main_instance_costs = {}

      return instances unless File.exist?(session_log_path)

      File.foreach(session_log_path) do |line|
        data = JSON.parse(line)
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
        # Track costs and calls for other instances
        elsif data.dig("event", "type") == "result"
          instances[instance_name][:calls] += 1
          if (cost = data.dig("event", "total_cost_usd"))
            # Initialize cost tracking for this instance
            cost_tracking[instance_name] ||= {
              accumulated: 0.0,
              last_seen: 0.0,
            }

            # Check if session was reset (cost went down)
            if cost < cost_tracking[instance_name][:last_seen]
              # Session was reset - add the previous session's total to accumulated
              cost_tracking[instance_name][:accumulated] += cost_tracking[instance_name][:last_seen]
            end

            # Update last seen cost
            cost_tracking[instance_name][:last_seen] = cost

            # Set the total cost (accumulated + current)
            instances[instance_name][:cost] = cost_tracking[instance_name][:accumulated] + cost
            instances[instance_name][:has_cost_data] = true
          end
        end
      rescue JSON::ParserError
        next
      end

      # Add main instance token costs to final totals
      main_instance_costs.each do |name, cost|
        instances[name][:cost] += cost if instances[name]
      end

      instances
    end
  end
end
