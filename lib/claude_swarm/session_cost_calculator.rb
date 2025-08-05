# frozen_string_literal: true

module ClaudeSwarm
  module SessionCostCalculator
    extend self

    # Calculate total cost from session log file
    # Returns a hash with:
    # - total_cost: Total cost in USD (handles session resets)
    # - instances_with_cost: Set of instance names that have cost data
    def calculate_total_cost(session_log_path)
      return { total_cost: 0.0, instances_with_cost: Set.new } unless File.exist?(session_log_path)

      # Track costs per instance, handling session resets
      instance_costs = {}
      instances_with_cost = Set.new

      File.foreach(session_log_path) do |line|
        data = JSON.parse(line)
        if data.dig("event", "type") == "result" && (cost = data.dig("event", "total_cost_usd"))
          instance_name = data["instance"]
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

      # Calculate total: accumulated + current cumulative for each instance
      total_cost = instance_costs.values.sum { |costs| costs[:accumulated] + costs[:last_seen] }

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

        # Track costs and calls
        if data.dig("event", "type") == "result"
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

      instances
    end
  end
end
