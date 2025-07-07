# frozen_string_literal: true

module ClaudeSwarm
  class ProcessTracker
    PIDS_DIR = "pids"

    def initialize(session_path)
      @session_path = session_path
      @pids_dir = File.join(@session_path, PIDS_DIR)
      ensure_pids_directory
    end

    def track_pid(pid, name)
      pid_file = File.join(@pids_dir, pid.to_s)
      File.write(pid_file, name)
    end

    def cleanup_all
      return unless Dir.exist?(@pids_dir)

      # Get all PID files
      pid_files = Dir.glob(File.join(@pids_dir, "*"))

      pid_files.each do |pid_file|
        pid = File.basename(pid_file).to_i
        name = begin
          File.read(pid_file).strip
        rescue StandardError
          "unknown"
        end

        begin
          # Check if process is still running
          Process.kill(0, pid)
          # If we get here, process is running, so kill it
          Process.kill("TERM", pid)
          puts "✓ Terminated MCP server: #{name} (PID: #{pid})"

          # Give it a moment to terminate gracefully
          sleep(0.1)

          # Force kill if still running
          begin
            Process.kill(0, pid)
            Process.kill("KILL", pid)
            puts "  → Force killed #{name} (PID: #{pid})"
          rescue Errno::ESRCH
            # Process is gone, which is what we want
          end
        rescue Errno::ESRCH
          # Process not found, already terminated
          puts "  → MCP server #{name} (PID: #{pid}) already terminated"
        rescue Errno::EPERM
          # Permission denied
          puts "  ⚠️  No permission to terminate #{name} (PID: #{pid})"
        end
      end

      # Clean up the pids directory
      FileUtils.rm_rf(@pids_dir)
    end

    class << self
      def cleanup_session(session_path)
        return unless Dir.exist?(File.join(session_path, PIDS_DIR))

        tracker = new(session_path)
        tracker.cleanup_all
      end
    end

    private

    def ensure_pids_directory
      FileUtils.mkdir_p(@pids_dir)
    end
  end
end
