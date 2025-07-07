# frozen_string_literal: true

require "English"
require "shellwords"
require "json"
require "fileutils"
require_relative "session_cost_calculator"

module ClaudeSwarm
  class Orchestrator
    include SystemUtils
    RUN_DIR = File.expand_path("~/.claude-swarm/run")

    def initialize(configuration, mcp_generator, vibe: false, prompt: nil, stream_logs: false, debug: false,
      restore_session_path: nil, worktree: nil)
      @config = configuration
      @generator = mcp_generator
      @vibe = vibe
      @prompt = prompt
      @stream_logs = stream_logs
      @debug = debug
      @restore_session_path = restore_session_path
      @session_path = nil
      # Store worktree option for later use
      @worktree_option = worktree
      @needs_worktree_manager = worktree.is_a?(String) || worktree == "" ||
        configuration.instances.values.any? { |inst| !inst[:worktree].nil? }
      # Store modified instances after worktree setup
      @modified_instances = nil
      # Track start time for runtime calculation
      @start_time = nil

      # Set environment variable for prompt mode to suppress output
      ENV["CLAUDE_SWARM_PROMPT"] = "1" if @prompt
    end

    def start
      # Track start time
      @start_time = Time.now

      if @restore_session_path
        unless @prompt
          puts "🔄 Restoring Claude Swarm: #{@config.swarm_name}"
          puts "😎 Vibe mode ON" if @vibe
          puts
        end

        # Use existing session path
        session_path = @restore_session_path
        @session_path = session_path
        ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path
        ENV["CLAUDE_SWARM_START_DIR"] = Dir.pwd

        # Create run symlink for restored session
        create_run_symlink

        unless @prompt
          puts "📝 Using existing session: #{session_path}/"
          puts
        end

        # Initialize process tracker
        @process_tracker = ProcessTracker.new(session_path)

        # Set up signal handlers to clean up child processes
        setup_signal_handlers

        # Check if the original session used worktrees
        restore_worktrees_if_needed(session_path)

        # Regenerate MCP configurations with session IDs for restoration
        @generator.generate_all
        unless @prompt
          puts "✓ Regenerated MCP configurations with session IDs"
          puts
        end
      else
        unless @prompt
          puts "🐝 Starting Claude Swarm: #{@config.swarm_name}"
          puts "😎 Vibe mode ON" if @vibe
          puts
        end

        # Generate and set session path for all instances
        session_path = SessionPath.generate(working_dir: Dir.pwd)
        SessionPath.ensure_directory(session_path)
        @session_path = session_path

        # Extract session ID from path (the timestamp part)
        @session_id = File.basename(session_path)

        ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path
        ENV["CLAUDE_SWARM_START_DIR"] = Dir.pwd

        # Create run symlink for new session
        create_run_symlink

        unless @prompt
          puts "📝 Session files will be saved to: #{session_path}/"
          puts
        end

        # Initialize process tracker
        @process_tracker = ProcessTracker.new(session_path)

        # Set up signal handlers to clean up child processes
        setup_signal_handlers

        # Create WorktreeManager if needed with session ID
        if @needs_worktree_manager
          cli_option = @worktree_option.is_a?(String) && !@worktree_option.empty? ? @worktree_option : nil
          @worktree_manager = WorktreeManager.new(cli_option, session_id: @session_id)
          puts "🌳 Setting up Git worktrees..." unless @prompt

          # Get all instances for worktree setup
          # Note: instances.values already includes the main instance
          all_instances = @config.instances.values

          @worktree_manager.setup_worktrees(all_instances)

          unless @prompt
            puts "✓ Worktrees created with branch: #{@worktree_manager.worktree_name}"
            puts
          end
        end

        # Generate all MCP configuration files
        @generator.generate_all
        unless @prompt
          puts "✓ Generated MCP configurations in session directory"
          puts
        end

        # Save swarm config path for restoration
        save_swarm_config_path(session_path)
      end

      # Execute before commands if specified
      before_commands = @config.before_commands
      if before_commands.any? && !@restore_session_path
        unless @prompt
          puts "⚙️  Executing before commands..."
          puts
        end

        success = execute_before_commands?(before_commands)
        unless success
          puts "❌ Before commands failed. Aborting swarm launch." unless @prompt
          cleanup_processes
          cleanup_run_symlink
          cleanup_worktrees
          exit(1)
        end

        unless @prompt
          puts "✓ Before commands completed successfully"
          puts
        end
      end

      # Launch the main instance (fetch after worktree setup to get modified paths)
      main_instance = @config.main_instance_config
      unless @prompt
        puts "🚀 Launching main instance: #{@config.main_instance}"
        puts "   Model: #{main_instance[:model]}"
        if main_instance[:directories].size == 1
          puts "   Directory: #{main_instance[:directory]}"
        else
          puts "   Directories:"
          main_instance[:directories].each { |dir| puts "     - #{dir}" }
        end
        puts "   Allowed tools: #{main_instance[:allowed_tools].join(", ")}" if main_instance[:allowed_tools].any?
        puts "   Disallowed tools: #{main_instance[:disallowed_tools].join(", ")}" if main_instance[:disallowed_tools]&.any?
        puts "   Connections: #{main_instance[:connections].join(", ")}" if main_instance[:connections].any?
        puts "   😎 Vibe mode ON for this instance" if main_instance[:vibe]
        puts
      end

      command = build_main_command(main_instance)
      if @debug && !@prompt
        puts "🏃 Running: #{format_command_for_display(command)}"
        puts
      end

      # Start log streaming thread if in non-interactive mode with --stream-logs
      log_thread = nil
      log_thread = start_log_streaming if @prompt && @stream_logs

      # Write the current process PID (orchestrator) to a file for easy access
      main_pid_file = File.join(@session_path, "main_pid")
      File.write(main_pid_file, Process.pid.to_s)

      # Execute the main instance - this will cascade to other instances via MCP
      Dir.chdir(main_instance[:directory]) do
        system!(*command)
      end

      # Clean up log streaming thread
      if log_thread
        log_thread.terminate
        log_thread.join
      end

      # Display runtime and cost summary
      display_summary

      # Clean up child processes and run symlink
      cleanup_processes
      cleanup_run_symlink
      cleanup_worktrees
    end

    private

    def execute_before_commands?(commands)
      log_file = File.join(@session_path, "session.log") if @session_path

      commands.each_with_index do |command, index|
        # Log the command execution to session log
        if @session_path
          File.open(log_file, "a") do |f|
            f.puts "[#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}] Executing before command #{index + 1}/#{commands.size}: #{command}"
          end
        end

        # Execute the command and capture output
        begin
          puts "Debug: Executing command #{index + 1}/#{commands.size}: #{command}" if @debug && !@prompt

          # Use system with output capture
          output = %x(#{command} 2>&1)
          success = $CHILD_STATUS.success?

          # Log the output
          if @session_path
            File.open(log_file, "a") do |f|
              f.puts "Command output:"
              f.puts output
              f.puts "Exit status: #{$CHILD_STATUS.exitstatus}"
              f.puts "-" * 80
            end
          end

          # Show output if in debug mode or if command failed
          if (@debug || !success) && !@prompt
            puts "Command #{index + 1} output:"
            puts output
            puts "Exit status: #{$CHILD_STATUS.exitstatus}"
          end

          unless success
            puts "❌ Before command #{index + 1} failed: #{command}" unless @prompt
            return false
          end
        rescue StandardError => e
          puts "Error executing before command #{index + 1}: #{e.message}" unless @prompt
          if @session_path
            File.open(log_file, "a") do |f|
              f.puts "Error: #{e.message}"
              f.puts "-" * 80
            end
          end
          return false
        end
      end

      true
    end

    def save_swarm_config_path(session_path)
      # Copy the YAML config file to the session directory
      config_copy_path = File.join(session_path, "config.yml")
      FileUtils.cp(@config.config_path, config_copy_path)

      # Save the original working directory
      start_dir_file = File.join(session_path, "start_directory")
      File.write(start_dir_file, Dir.pwd)

      # Save session metadata
      metadata = {
        "start_directory" => Dir.pwd,
        "timestamp" => Time.now.utc.iso8601,
        "start_time" => @start_time.utc.iso8601,
        "swarm_name" => @config.swarm_name,
        "claude_swarm_version" => VERSION,
      }

      # Add worktree info if applicable
      metadata["worktree"] = @worktree_manager.session_metadata if @worktree_manager

      metadata_file = File.join(session_path, "session_metadata.json")
      File.write(metadata_file, JSON.pretty_generate(metadata))
    end

    def setup_signal_handlers
      ["INT", "TERM", "QUIT"].each do |signal|
        Signal.trap(signal) do
          puts "\n🛑 Received #{signal} signal, cleaning up..."
          display_summary
          cleanup_processes
          cleanup_run_symlink
          cleanup_worktrees
          exit
        end
      end
    end

    def cleanup_processes
      @process_tracker.cleanup_all
      puts "✓ Cleanup complete"
    rescue StandardError => e
      puts "⚠️  Error during cleanup: #{e.message}"
    end

    def cleanup_worktrees
      return unless @worktree_manager

      @worktree_manager.cleanup_worktrees
    rescue StandardError => e
      puts "⚠️  Error during worktree cleanup: #{e.message}"
    end

    def display_summary
      return unless @session_path && @start_time

      end_time = Time.now
      runtime_seconds = (end_time - @start_time).to_i

      # Update session metadata with end time
      update_session_end_time(end_time)

      # Calculate total cost from session logs
      total_cost = calculate_total_cost

      puts
      puts "=" * 50
      puts "🏁 Claude Swarm Summary"
      puts "=" * 50
      puts "Runtime: #{format_duration(runtime_seconds)}"
      puts "Total Cost: #{format_cost(total_cost)}"
      puts "Session: #{File.basename(@session_path)}"
      puts "=" * 50
    end

    def update_session_end_time(end_time)
      metadata_file = File.join(@session_path, "session_metadata.json")
      return unless File.exist?(metadata_file)

      metadata = JSON.parse(File.read(metadata_file))
      metadata["end_time"] = end_time.utc.iso8601
      metadata["duration_seconds"] = (end_time - @start_time).to_i

      File.write(metadata_file, JSON.pretty_generate(metadata))
    rescue StandardError => e
      puts "⚠️  Error updating session metadata: #{e.message}" unless @prompt
    end

    def calculate_total_cost
      log_file = File.join(@session_path, "session.log.json")
      result = SessionCostCalculator.calculate_total_cost(log_file)

      # Check if main instance has cost data
      main_instance_name = @config.main_instance
      @main_has_cost = result[:instances_with_cost].include?(main_instance_name)

      result[:total_cost]
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

    def format_cost(cost)
      cost_str = format("$%.4f", cost)
      cost_str += " (excluding main instance)" unless @main_has_cost
      cost_str
    end

    def create_run_symlink
      return unless @session_path

      FileUtils.mkdir_p(RUN_DIR)

      # Session ID is the last part of the session path
      session_id = File.basename(@session_path)
      symlink_path = File.join(RUN_DIR, session_id)

      # Remove stale symlink if exists
      File.unlink(symlink_path) if File.symlink?(symlink_path)

      # Create new symlink
      File.symlink(@session_path, symlink_path)
    rescue StandardError => e
      # Don't fail the process if symlink creation fails
      puts "⚠️  Warning: Could not create run symlink: #{e.message}" unless @prompt
    end

    def cleanup_run_symlink
      return unless @session_path

      session_id = File.basename(@session_path)
      symlink_path = File.join(RUN_DIR, session_id)
      File.unlink(symlink_path) if File.symlink?(symlink_path)
    rescue StandardError
      # Ignore errors during cleanup
    end

    def start_log_streaming
      Thread.new do
        session_log_path = File.join(ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil), "session.log")

        # Wait for log file to be created
        sleep(0.1) until File.exist?(session_log_path)

        # Open file and seek to end
        File.open(session_log_path, "r") do |file|
          file.seek(0, IO::SEEK_END)

          loop do
            changes = file.read
            if changes
              print(changes)
              $stdout.flush
            else
              sleep(0.1)
            end
          end
        end
      rescue StandardError
        # Silently handle errors (file might be deleted, process might end, etc.)
      end
    end

    def format_command_for_display(command)
      command.map do |part|
        if part.match?(/\s|'|"/)
          "'#{part.gsub("'", "'\\\\''")}'"
        else
          part
        end
      end.join(" ")
    end

    def build_main_command(instance)
      parts = [
        "claude",
        "--model",
        instance[:model],
      ]

      # Add resume flag if restoring session
      if @restore_session_path
        # Look for main instance state file
        main_instance_name = @config.main_instance
        state_files = Dir.glob(File.join(@restore_session_path, "state", "*.json"))

        # Find the state file for the main instance
        state_files.each do |state_file|
          state_data = JSON.parse(File.read(state_file))
          next unless state_data["instance_name"] == main_instance_name

          claude_session_id = state_data["claude_session_id"]
          if claude_session_id
            parts << "--resume"
            parts << claude_session_id
          end
          break
        end
      end

      if @vibe || instance[:vibe]
        parts << "--dangerously-skip-permissions"
      else
        # Build allowed tools list including MCP connections
        allowed_tools = instance[:allowed_tools].dup

        # Add mcp__instance_name for each connection
        instance[:connections].each do |connection_name|
          allowed_tools << "mcp__#{connection_name}"
        end

        # Add allowed tools if any
        if allowed_tools.any?
          tools_str = allowed_tools.join(",")
          parts << "--allowedTools"
          parts << tools_str
        end

        # Add disallowed tools if any
        if instance[:disallowed_tools]&.any?
          disallowed_tools_str = instance[:disallowed_tools].join(",")
          parts << "--disallowedTools"
          parts << disallowed_tools_str
        end
      end

      if instance[:prompt]
        parts << "--append-system-prompt"
        parts << instance[:prompt]
      end

      parts << "--debug" if @debug

      # Add additional directories with --add-dir
      if instance[:directories].size > 1
        instance[:directories][1..].each do |additional_dir|
          parts << "--add-dir"
          parts << additional_dir
        end
      end

      mcp_config_path = @generator.mcp_config_path(@config.main_instance)
      parts << "--mcp-config"
      parts << mcp_config_path

      if @prompt
        parts << "-p"
        parts << @prompt
      else
        parts << "#{instance[:prompt]}\n\nNow just say 'I am ready to start'"
      end
    end

    def restore_worktrees_if_needed(session_path)
      metadata_file = File.join(session_path, "session_metadata.json")
      return unless File.exist?(metadata_file)

      metadata = JSON.parse(File.read(metadata_file))
      worktree_data = metadata["worktree"]
      return unless worktree_data && worktree_data["enabled"]

      unless @prompt
        puts "🌳 Restoring Git worktrees..."
        puts
      end

      # Restore worktrees using the saved configuration
      # Extract session ID from the session path
      session_id = File.basename(session_path)
      @worktree_manager = WorktreeManager.new(worktree_data["shared_name"], session_id: session_id)

      # Get all instances and restore their worktree paths
      all_instances = @config.instances.values
      @worktree_manager.setup_worktrees(all_instances)

      return if @prompt

      puts "✓ Worktrees restored with branch: #{@worktree_manager.worktree_name}"
      puts
    end
  end
end
