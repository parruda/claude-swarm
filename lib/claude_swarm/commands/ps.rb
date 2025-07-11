# frozen_string_literal: true

module ClaudeSwarm
  module Commands
    class Ps
      RUN_DIR = File.expand_path("~/.claude-swarm/run")

      def execute
        unless Dir.exist?(RUN_DIR)
          puts "No active sessions"
          return
        end

        sessions = []

        # Read all symlinks in run directory
        Dir.glob("#{RUN_DIR}/*").each do |symlink|
          next unless File.symlink?(symlink)

          begin
            session_dir = File.readlink(symlink)
            # Skip if target doesn't exist (stale symlink)
            next unless Dir.exist?(session_dir)

            session_info = parse_session_info(session_dir)
            sessions << session_info if session_info
          rescue StandardError
            # Skip problematic symlinks
          end
        end

        if sessions.empty?
          puts "No active sessions"
          return
        end

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
        puts "\n⚠️  \e[3mTotal cost does not include the cost of the main instance\e[0m\n\n"
        puts header
        puts "-" * header.length

        # Display sessions sorted by start time (newest first)
        sessions.sort_by { |s| s[:start_time] }.reverse.each do |session|
          cost_str = format("$%.4f", session[:cost])
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

      def parse_session_info(session_dir)
        session_id = File.basename(session_dir)

        # Load config for swarm name and main directory
        config_file = File.join(session_dir, "config.yml")
        return unless File.exist?(config_file)

        config = YAML.load_file(config_file)
        swarm_name = config.dig("swarm", "name") || "Unknown"
        main_instance = config.dig("swarm", "main")

        # Get base directory from session metadata or root_directory file
        base_dir = ClaudeSwarm.root_dir
        root_dir_file = File.join(session_dir, "root_directory")
        base_dir = File.read(root_dir_file).strip if File.exist?(root_dir_file)

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
        total_cost = SessionCostCalculator.calculate_simple_total(log_file)

        # Get uptime from session metadata or fallback to directory creation time
        start_time = get_start_time(session_dir)
        uptime = format_duration(Time.now - start_time)

        {
          id: session_id,
          name: swarm_name,
          cost: total_cost,
          uptime: uptime,
          directory: directories_str,
          start_time: start_time,
        }
      rescue StandardError
        nil
      end

      def get_start_time(session_dir)
        # Try to get from session metadata first
        metadata_file = File.join(session_dir, "session_metadata.json")
        if File.exist?(metadata_file)
          metadata = JSON.parse(File.read(metadata_file))
          return Time.parse(metadata["start_time"]) if metadata["start_time"]
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

        metadata = JSON.parse(File.read(session_metadata_file))
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
