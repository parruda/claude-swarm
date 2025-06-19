# frozen_string_literal: true

require "fileutils"

module ClaudeSwarm
  module SessionPath
    SESSIONS_DIR = "sessions"

    class << self
      def swarm_home
        ENV["CLAUDE_SWARM_HOME"] || File.expand_path("~/.claude-swarm")
      end

      # Convert a directory path to a safe folder name using + as separator
      def project_folder_name(working_dir = Dir.pwd)
        # Don't expand path if it's already expanded (avoids double expansion on Windows)
        path = working_dir.start_with?("/") || working_dir.match?(/^[A-Za-z]:/) ? working_dir : File.expand_path(working_dir)

        # Handle Windows drive letters (C:\ → C)
        path = path.gsub(/^([A-Za-z]):/, '\1')

        # Remove leading slash/backslash
        path = path.sub(%r{^[/\\]}, "")

        # Replace all path separators with +
        path.gsub(%r{[/\\]}, "+")
      end

      # Generate a full session path for a given directory and timestamp
      def generate(working_dir: Dir.pwd, timestamp: Time.now.strftime("%Y%m%d_%H%M%S"))
        project_name = project_folder_name(working_dir)
        File.join(swarm_home, SESSIONS_DIR, project_name, timestamp)
      end

      # Ensure the session directory exists
      def ensure_directory(session_path)
        FileUtils.mkdir_p(session_path)

        # Add .gitignore to swarm home if it doesn't exist
        gitignore_path = File.join(swarm_home, ".gitignore")
        File.write(gitignore_path, "*\n") unless File.exist?(gitignore_path)
      end

      # Get the session path from environment (required)
      def from_env
        ENV["CLAUDE_SWARM_SESSION_PATH"] or raise "CLAUDE_SWARM_SESSION_PATH not set"
      end
    
      # Find a session path by ID
      def find_by_id(session_id)
        run_symlink = File.join(File.expand_path(File.join(swarm_home, "run")), session_id)
        if File.symlink?(run_symlink)
          File.readlink(run_symlink)
        else
          # Search in sessions directory
          Dir.glob(File.expand_path("#{File.join(swarm_home, SESSIONS_DIR)}/*/*")).find do |path|
            File.basename(path) == session_id
          end
        end
      end

      # Find the most recent session path
      def find_most_recent
        sessions_dir = File.join(swarm_home, SESSIONS_DIR)
        return nil unless Dir.exist?(sessions_dir)

        # Directly find all session directories with config files
        # Pattern matches: sessions_dir/project_dir/timestamp_dir/config.yml
        session_paths = Dir.glob(File.join(sessions_dir, "*", "*", "config.yml"))
                           .map { |config_file| File.dirname(config_file) }
                           .uniq

        return nil if session_paths.empty?

        # Sort by timestamp in directory name (newest first)
        session_paths.sort_by { |path| File.basename(path) }.reverse.first
      end
    end
  end
end
