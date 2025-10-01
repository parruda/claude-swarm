# frozen_string_literal: true

module ClaudeSwarm
  module Commands
    class Show
      def execute(session_id)
        session_path = find_session_path(session_id)
        unless session_path
          puts "Session not found: #{session_id}"
          exit(1)
        end

        # Load config to get main instance name
        config = YamlLoader.load_config_file(File.join(session_path, "config.yml"))
        main_instance_name = config.dig("swarm", "main")

        # Parse all events to build instance data
        log_file = File.join(session_path, "session.log.json")
        instances = SessionCostCalculator.parse_instance_hierarchy(log_file)

        # Calculate total cost (excluding main if not available)
        total_cost = instances.values.sum { |i| i[:cost] }
        cost_display = if instances[main_instance_name] && instances[main_instance_name][:has_cost_data]
          format("$%.4f", total_cost)
        else
          "#{format("$%.4f", total_cost)} (excluding main instance)"
        end

        # Display session info
        puts "Session: #{session_id}"
        puts "Session Path: #{session_path}"
        puts "Swarm: #{config.dig("swarm", "name")}"

        # Display runtime if available
        runtime_info = get_runtime_info(session_path)
        puts "Runtime: #{runtime_info}" if runtime_info

        puts "Total Cost: #{cost_display}"

        # Try to read root directory
        root_dir_file = File.join(session_path, "root_directory")
        puts "Root Directory: #{File.read(root_dir_file).strip}" if File.exist?(root_dir_file)

        puts
        puts "Instance Hierarchy:"
        puts "-" * 50

        # Find root instances
        roots = instances.values.select { |i| i[:called_by].empty? }
        roots.each do |instance|
          display_instance_tree(instance, instances, 0, main_instance_name)
        end

        # Add note about interactive main instance
        return if instances[main_instance_name]&.dig(:has_cost_data)

        puts
        puts "Note: Main instance (#{main_instance_name}) cost is not tracked in interactive mode."
        puts "      View costs directly in the Claude interface."
      end

      private

      def find_session_path(session_id)
        # First check the run directory
        run_symlink = ClaudeSwarm.joined_run_dir(session_id)
        if File.symlink?(run_symlink)
          target = File.readlink(run_symlink)
          return target if Dir.exist?(target)
        end

        # Fall back to searching all sessions
        Dir.glob(ClaudeSwarm.joined_sessions_dir("*", "*")).find do |path|
          File.basename(path) == session_id
        end
      end

      def get_runtime_info(session_path)
        metadata_file = File.join(session_path, "session_metadata.json")
        metadata = JsonHandler.parse_file(metadata_file)
        return unless metadata

        if metadata["duration_seconds"]
          # Session has completed
          format_duration(metadata["duration_seconds"])
        elsif metadata["start_time"]
          # Session is still running or was interrupted
          start_time = Time.parse(metadata["start_time"])
          duration = (Time.now - start_time).to_i
          "#{format_duration(duration)} (active)"
        end
      rescue StandardError
        nil
      end

      def format_duration(seconds)
        hours = seconds / 3600
        minutes = (seconds % 3600) / 60
        secs = seconds % 60

        parts = []
        parts << "#{hours}h" if hours.positive?
        parts << "#{minutes}m" if minutes.positive?
        parts << "#{secs}s"

        parts.join(" ")
      end

      def display_instance_tree(instance, all_instances, level, main_instance_name)
        indent = "  " * level
        prefix = level.zero? ? "├─" : "└─"

        # Display instance name with special marker for main
        instance_display = instance[:name]
        instance_display += " [main]" if instance[:name] == main_instance_name

        puts "#{indent}#{prefix} #{instance_display} (#{instance[:id]})"

        # Display cost - show n/a for main instance without cost data
        cost_display = if instance[:name] == main_instance_name && !instance[:has_cost_data]
          "n/a (interactive)"
        else
          format("$%.4f", instance[:cost])
        end

        puts "#{indent}   Cost: #{cost_display} | Calls: #{instance[:calls]}"

        # Display children
        children = instance[:calls_to].map { |name| all_instances[name] }.compact
        children.each do |child|
          # Don't recurse if we've already shown this instance (avoid cycles)
          next if level.positive? && child[:called_by].size > 1

          display_instance_tree(child, all_instances, level + 1, main_instance_name)
        end
      end
    end
  end
end
