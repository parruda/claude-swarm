# frozen_string_literal: true

module ClaudeSwarm
  module Commands
    class Ps
      def execute
        run_dir = ClaudeSwarm.joined_run_dir
        unless Dir.exist?(run_dir)
          puts "No active sessions"
          return
        end

        # Read all symlinks in run directory and process them
        sessions = Dir.glob("#{run_dir}/*").filter_map do |symlink|
          process_symlink(symlink)
        end

        if sessions.empty?
          puts "No active sessions"
          return
        end

        # Check if any session is missing main instance costs
        any_missing_main = sessions.any? { |s| !s[:main_has_cost] }

        # Column widths
        col_session = 15
        col_swarm = 25
        col_cost = 12
        col_uptime = 10

        # Display header with proper spacing
        header = "#{
          "SESSION_ID".ljust(col_session)
        }  #{
          "SWARM_NAME".ljust(col_swarm)
        }  #{
          "TOTAL_COST".ljust(col_cost)
        }  #{
          "UPTIME".ljust(col_uptime)
        }  DIRECTORY"

        # Only show warning if any session is missing main instance costs
        if any_missing_main
          puts "\n⚠️  \e[3mTotal cost does not include the cost of the main instance for some sessions\e[0m\n\n"
        else
          puts
        end

        puts header
        puts "-" * header.length

        # Display sessions sorted by start time (newest first)
        sessions.sort_by { |s| s[:start_time] }.reverse.each do |session|
          cost_str = format("$%.4f", session[:cost])
          # Add asterisk if this session is missing main instance cost
          cost_str += "*" unless session[:main_has_cost]

          puts "#{
            session[:id].ljust(col_session)
          }  #{
            truncate(session[:name], col_swarm).ljust(col_swarm)
          }  #{
            cost_str.ljust(col_cost)
          }  #{
            session[:uptime].ljust(col_uptime)
          }  #{session[:directory]}"
        end
      end

      private

      def process_symlink(symlink)
        session_dir = File.readlink(symlink)
        session_id = File.basename(session_dir)
        # Skip if target doesn't exist (stale symlink)
        return unless Dir.exist?(session_dir)

        parse_session_info(session_id, session_dir)
      rescue Errno::EINVAL
        # Not a symlink, skip it
        nil
      rescue StandardError => e
        # Try to get session_id if we have session_dir
        warn("⚠️  Skipping session #{session_id}: #{e.message}")
        nil
      end

      def parse_session_info(session_id, session_dir)
        # Load config for swarm name and main directory
        config_file = File.join(session_dir, "config.yml")
        return unless File.exist?(config_file)

        config = YamlLoader.load_config_file(config_file)
        swarm_name = config.dig("swarm", "name") || "Unknown"
        main_instance = config.dig("swarm", "main")

        # Get base directory from session metadata or root_directory file
        root_dir_file = File.join(session_dir, "root_directory")
        base_dir = File.exist?(root_dir_file) ? File.read(root_dir_file).strip : Dir.pwd

        # Get all directories - handle both string and array formats
        dir_config = config.dig("swarm", "instances", main_instance, "directory")
        directories = if dir_config.is_a?(Array)
          dir_config
        else
          [dir_config || "."]
        end

        # Expand paths relative to the base directory
        expanded_directories = directories.map do |dir|
          File.expand_path(dir, base_dir)
        end

        # Check for worktree information in session metadata
        expanded_directories = apply_worktree_paths(expanded_directories, session_dir)

        directories_str = expanded_directories.join(", ")

        # Calculate total cost from JSON log
        log_file = File.join(session_dir, "session.log.json")
        cost_result = SessionCostCalculator.calculate_total_cost(log_file)
        total_cost = cost_result[:total_cost]

        # Check if main instance has cost data
        instances_with_cost = cost_result[:instances_with_cost]
        main_has_cost = main_instance && instances_with_cost.include?(main_instance)

        # Get uptime from session metadata or fallback to directory creation time
        start_time = get_start_time(session_dir)
        uptime = format_duration(Time.now - start_time)

        {
          id: session_id,
          name: swarm_name,
          cost: total_cost,
          main_has_cost: main_has_cost,
          uptime: uptime,
          directory: directories_str,
          start_time: start_time,
        }
      end

      def get_start_time(session_dir)
        # Try to get from session metadata first
        metadata_file = File.join(session_dir, "session_metadata.json")
        metadata = JsonHandler.parse_file(metadata_file)

        if metadata && metadata["start_time"]
          return Time.parse(metadata["start_time"])
        end

        # Fallback to directory creation time
        File.stat(session_dir).ctime
      rescue StandardError
        # If anything fails, use directory creation time
        File.stat(session_dir).ctime
      end

      def format_duration(seconds)
        if seconds < 60
          "#{seconds.to_i}s"
        elsif seconds < 3600
          "#{(seconds / 60).to_i}m"
        elsif seconds < 86_400
          "#{(seconds / 3600).to_i}h"
        else
          "#{(seconds / 86_400).to_i}d"
        end
      end

      def truncate(str, length)
        str.length > length ? "#{str[0...length - 2]}.." : str
      end

      def apply_worktree_paths(directories, session_dir)
        session_metadata_file = File.join(session_dir, "session_metadata.json")
        return directories unless File.exist?(session_metadata_file)

        metadata = JsonHandler.parse_file!(session_metadata_file)
        worktree_info = metadata["worktree"]
        return directories unless worktree_info && worktree_info["enabled"]

        # Get the created worktree paths
        created_paths = worktree_info["created_paths"] || {}

        # For each directory, find the appropriate worktree path
        directories.map do |dir|
          # Find if this directory has a worktree created
          repo_root = find_git_root(dir)
          next dir unless repo_root

          # Look for a worktree with this repo root
          worktree_key = created_paths.keys.find { |key| key.start_with?("#{repo_root}:") }
          worktree_key ? created_paths[worktree_key] : dir
        end
      end

      def worktree_path_for(dir, worktree_name)
        git_root = find_git_root(dir)
        git_root ? File.join(git_root, ".worktrees", worktree_name) : dir
      end

      def find_git_root(dir)
        current = File.expand_path(dir)
        while current != "/"
          return current if File.exist?(File.join(current, ".git"))

          current = File.dirname(current)
        end
        nil
      end
    end
  end
end
