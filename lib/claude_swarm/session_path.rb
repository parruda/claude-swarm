# frozen_string_literal: true

module ClaudeSwarm
  module SessionPath
    class << self
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

      # Generate a full session path for a given directory and session ID
      def generate(working_dir: Dir.pwd, session_id: SecureRandom.uuid)
        project_name = project_folder_name(working_dir)
        ClaudeSwarm.joined_sessions_dir(project_name, session_id)
      end

      # Ensure the session directory exists
      def ensure_directory(session_path)
        FileUtils.mkdir_p(session_path)

        # Add .gitignore to swarm home if it doesn't exist
        gitignore_path = ClaudeSwarm.joined_home_dir(".gitignore")
        File.write(gitignore_path, "*\n") unless File.exist?(gitignore_path)
      end

      # Get the session path from environment (required)
      def from_env
        ENV["CLAUDE_SWARM_SESSION_PATH"] or raise "CLAUDE_SWARM_SESSION_PATH not set"
      end
    end
  end
end
