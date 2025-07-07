# frozen_string_literal: true

module ClaudeSwarm
  module SessionCostCalculator
    extend self

    # Calculate total cost from session log file
    # Returns a hash with:
    # - total_cost: Total cost in USD
    # - instances_with_cost: Set of instance names that have cost data
    def calculate_total_cost(session_log_path)
      return { total_cost: 0.0, instances_with_cost: Set.new } unless File.exist?(session_log_path)

      total_cost = 0.0
      instances_with_cost = Set.new

      File.foreach(session_log_path) do |line|
        data = JSON.parse(line)
        if data.dig("event", "type") == "result" && (cost = data.dig("event", "total_cost_usd"))
          total_cost += cost
          instances_with_cost << data["instance"]
        end
      rescue JSON::ParserError
        next
      end

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
            instances[instance_name][:cost] += cost
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
