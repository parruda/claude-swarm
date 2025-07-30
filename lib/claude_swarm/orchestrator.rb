# frozen_string_literal: true

module ClaudeSwarm
  class Orchestrator
    include SystemUtils

    attr_reader :config, :session_path, :session_log_path

    RUN_DIR = File.expand_path("~/.claude-swarm/run")
    ["INT", "TERM", "QUIT"].each do |signal|
      Signal.trap(signal) do
        puts "\n🛑 Received #{signal} signal."
      end
    end

    def initialize(configuration, mcp_generator, vibe: false, prompt: nil, interactive_prompt: nil, stream_logs: false, debug: false,
      restore_session_path: nil, worktree: nil, session_id: nil)
      @config = configuration
      @generator = mcp_generator
      @vibe = vibe
      @non_interactive_prompt = prompt
      @interactive_prompt = interactive_prompt
      @stream_logs = stream_logs
      @debug = debug
      @restore_session_path = restore_session_path
      @session_path = nil
      @session_log_path = nil
      @provided_session_id = session_id
      # Store worktree option for later use
      @worktree_option = worktree
      @needs_worktree_manager = worktree.is_a?(String) || worktree == "" ||
        configuration.instances.values.any? { |inst| !inst[:worktree].nil? }
      # Store modified instances after worktree setup
      @modified_instances = nil
      # Track start time for runtime calculation
      @start_time = nil

      # Set environment variable for prompt mode to suppress output
      ENV["CLAUDE_SWARM_PROMPT"] = "1" if @non_interactive_prompt
    end

    def start
      # Track start time
      @start_time = Time.now

      if @restore_session_path
        non_interactive_output do
          puts "🔄 Restoring Claude Swarm: #{@config.swarm_name}"
          puts "😎 Vibe mode ON" if @vibe
        end

        # Use existing session path
        session_path = @restore_session_path
        @session_path = session_path
        @session_log_path = File.join(@session_path, "session.log")
        ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path
        ENV["CLAUDE_SWARM_ROOT_DIR"] = ClaudeSwarm.root_dir

        # Create run symlink for restored session
        create_run_symlink

        non_interactive_output do
          puts "📝 Using existing session: #{session_path}/"
        end

        # Initialize process tracker
        @process_tracker = ProcessTracker.new(session_path)

        # Check if the original session used worktrees
        restore_worktrees_if_needed(session_path)

        # Regenerate MCP configurations with session IDs for restoration
        @generator.generate_all
        non_interactive_output do
          puts "✓ Regenerated MCP configurations with session IDs"
        end
      else
        non_interactive_output do
          puts "🐝 Starting Claude Swarm: #{@config.swarm_name}"
          puts "😎 Vibe mode ON" if @vibe
        end

        # Generate and set session path for all instances
        session_params = { working_dir: ClaudeSwarm.root_dir }
        session_params[:session_id] = @provided_session_id if @provided_session_id
        session_path = SessionPath.generate(**session_params)
        SessionPath.ensure_directory(session_path)
        @session_path = session_path
        @session_log_path = File.join(@session_path, "session.log")

        # Extract session ID from path (the timestamp part)
        @session_id = File.basename(session_path)

        ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path
        ENV["CLAUDE_SWARM_ROOT_DIR"] = ClaudeSwarm.root_dir

        # Create run symlink for new session
        create_run_symlink

        non_interactive_output do
          puts "📝 Session files will be saved to: #{session_path}/"
        end

        # Initialize process tracker
        @process_tracker = ProcessTracker.new(session_path)

        # Create WorktreeManager if needed with session ID
        if @needs_worktree_manager
          cli_option = @worktree_option.is_a?(String) && !@worktree_option.empty? ? @worktree_option : nil
          @worktree_manager = WorktreeManager.new(cli_option, session_id: @session_id)
          non_interactive_output { print("🌳 Setting up Git worktrees...") }

          # Get all instances for worktree setup
          # Note: instances.values already includes the main instance
          all_instances = @config.instances.values

          @worktree_manager.setup_worktrees(all_instances)

          non_interactive_output do
            puts "✓ Worktrees created with branch: #{@worktree_manager.worktree_name}"
          end
        end

        # Generate all MCP configuration files
        @generator.generate_all
        non_interactive_output do
          puts "✓ Generated MCP configurations in session directory"
        end

        # Save swarm config path for restoration
        save_swarm_config_path(session_path)
      end

      # Launch the main instance (fetch after worktree setup to get modified paths)
      main_instance = @config.main_instance_config
      non_interactive_output do
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
      end

      command = build_main_command(main_instance)
      if @debug
        non_interactive_output do
          puts "🏃 Running: #{format_command_for_display(command)}"
        end
      end

      # Start log streaming thread if in non-interactive mode with --stream-logs
      log_thread = nil
      log_thread = start_log_streaming if @non_interactive_prompt && @stream_logs

      # Write the current process PID (orchestrator) to a file for easy access
      main_pid_file = File.join(@session_path, "main_pid")
      File.write(main_pid_file, Process.pid.to_s)

      # Execute the main instance - this will cascade to other instances via MCP
      Dir.chdir(main_instance[:directory]) do
        # Execute before commands if specified
        before_commands = @config.before_commands
        if before_commands.any? && !@restore_session_path
          non_interactive_output do
            puts "⚙️  Executing before commands..."
          end

          success = execute_before_commands?(before_commands)
          unless success
            non_interactive_output { print("❌ Before commands failed. Aborting swarm launch.") }
            cleanup_processes
            cleanup_run_symlink
            cleanup_worktrees
            exit(1)
          end

          non_interactive_output do
            puts "✓ Before commands completed successfully"
          end
        end

        # Execute main Claude instance with unbundled environment to avoid bundler conflicts
        # This ensures the main instance runs in a clean environment without inheriting
        # Claude Swarm's BUNDLE_* environment variables
        Bundler.with_unbundled_env do
          if @non_interactive_prompt
            stream_to_session_log(*command)
          else
            system!(*command)
          end
        end
      end

      # Clean up log streaming thread
      if log_thread
        log_thread.terminate
        log_thread.join
      end

      # Display runtime and cost summary
      display_summary

      # Execute after commands if specified
      after_commands = @config.after_commands
      if after_commands.any? && !@restore_session_path
        Dir.chdir(main_instance[:directory]) do
          non_interactive_output do
            print("⚙️  Executing after commands...")
          end

          success = execute_after_commands?(after_commands)
          unless success
            non_interactive_output do
              puts "⚠️  Some after commands failed"
            end
          end
        end
      end

      # Clean up child processes and run symlink
      cleanup_processes
      cleanup_run_symlink
      cleanup_worktrees
    end

    private

    def non_interactive_output
      return if @non_interactive_prompt

      yield
      puts
    end

    def execute_before_commands?(commands)
      execute_commands(commands, phase: "before", fail_fast: true)
    end

    def execute_after_commands?(commands)
      execute_commands(commands, phase: "after", fail_fast: false)
    end

    def save_swarm_config_path(session_path)
      # Copy the YAML config file to the session directory
      config_copy_path = File.join(session_path, "config.yml")
      FileUtils.cp(@config.config_path, config_copy_path)

      # Save the root directory
      root_dir_file = File.join(session_path, "root_directory")
      File.write(root_dir_file, ClaudeSwarm.root_dir)

      # Save session metadata
      metadata_file = File.join(session_path, "session_metadata.json")
      File.write(metadata_file, JSON.pretty_generate(build_session_metadata))
    end

    def build_session_metadata
      {
        "root_directory" => ClaudeSwarm.root_dir,
        "timestamp" => Time.now.utc.iso8601,
        "start_time" => @start_time.utc.iso8601,
        "swarm_name" => @config.swarm_name,
        "claude_swarm_version" => VERSION,
      }.tap do |metadata|
        # Add worktree info if applicable
        metadata["worktree"] = @worktree_manager.session_metadata if @worktree_manager
      end
    end

    def cleanup_processes
      @process_tracker.cleanup_all
      puts "✓ Cleanup complete"
    rescue StandardError => e
      puts "⚠️  Error during cleanup: #{e.message}"
    end

    def cleanup_worktrees
      @worktree_manager&.cleanup_worktrees
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
      non_interactive_output { print("⚠️  Error updating session metadata: #{e.message}") }
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
      non_interactive_output { print("⚠️  Warning: Could not create run symlink: #{e.message}") }
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
        # Wait for log file to be created
        sleep(0.1) until File.exist?(@session_log_path)

        # Open file and seek to end
        File.open(@session_log_path, "r") do |file|
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
      parts = ["claude"]

      # Only add --model if ANTHROPIC_MODEL env var is not set
      unless ENV["ANTHROPIC_MODEL"]
        parts << "--model"
        parts << instance[:model]
      end

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

      # Always add instance prompt if it exists
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

      # Handle different modes
      if @non_interactive_prompt
        # Non-interactive mode with -p
        parts << "-p"
        parts << @non_interactive_prompt
        parts << "--verbose"
        parts << "--output-format=stream-json"
      elsif @interactive_prompt
        # Interactive mode with initial prompt (no -p flag)
        parts << @interactive_prompt
      end
      # else: Interactive mode without initial prompt - nothing to add

      parts
    end

    def restore_worktrees_if_needed(session_path)
      metadata_file = File.join(session_path, "session_metadata.json")
      return unless File.exist?(metadata_file)

      metadata = JSON.parse(File.read(metadata_file))
      worktree_data = metadata["worktree"]
      return unless worktree_data && worktree_data["enabled"]

      non_interactive_output do
        puts "🌳 Restoring Git worktrees..."
      end

      # Restore worktrees using the saved configuration
      # Extract session ID from the session path
      session_id = File.basename(session_path)
      @worktree_manager = WorktreeManager.new(worktree_data["shared_name"], session_id: session_id)

      # Get all instances and restore their worktree paths
      all_instances = @config.instances.values
      @worktree_manager.setup_worktrees(all_instances)

      non_interactive_output do
        puts "✓ Worktrees restored with branch: #{@worktree_manager.worktree_name}"
      end
    end

    def stream_to_session_log(*command)
      # Setup logger for session logging
      logger = Logger.new(@session_log_path, level: :info, progname: @config.main_instance)

      # Use Open3.popen2e to capture stdout and stderr merged for formatting
      Open3.popen2e(*command) do |stdin, stdout_and_stderr, wait_thr|
        stdin.close

        # Read and process the merged output
        stdout_and_stderr.each_line do |line|
          # Try to parse and prettify JSON lines

          json_data = JSON.parse(line.chomp)
          pretty_json = JSON.pretty_generate(json_data)
          logger.info { pretty_json }
        rescue JSON::ParserError
          # Warn about non-JSON output since we expect stream-json format
          warn("⚠️  Warning: Non-JSON output detected in stream-json mode: #{line.chomp}")
          # Log the line as-is
          logger.info { line.chomp }
        end

        wait_thr.value
      end
    end

    def execute_commands(commands, phase:, fail_fast:)
      all_succeeded = true

      # Setup logger for session logging if we have a session path
      logger = Logger.new(@session_log_path, level: :info)

      commands.each_with_index do |command, index|
        # Log the command execution to session log
        logger.info { "Executing #{phase} command #{index + 1}/#{commands.size}: #{command}" }

        # Execute the command and capture output
        begin
          if @debug
            non_interactive_output do
              debug_prefix = phase == "after" ? "after " : ""
              print("Debug: Executing #{debug_prefix} command #{index + 1}/#{commands.size}: #{format_command_for_display(command)}")
            end
          end

          output = %x(#{command} 2>&1)
          success = $CHILD_STATUS.success?
          output_separator = "-" * 80

          logger.info { "Command output:" }
          logger.info { output }
          logger.info { "Exit status: #{$CHILD_STATUS.exitstatus}" }
          logger.info { output_separator }

          # Show output if in debug mode or if command failed
          if @debug || !success
            non_interactive_output do
              output_prefix = phase == "after" ? "After command" : "Command"
              puts "#{output_prefix} #{index + 1} output:"
              puts output
              print("Exit status: #{$CHILD_STATUS.exitstatus}")
            end
          end

          unless success
            error_prefix = phase.capitalize
            non_interactive_output { print("❌ #{error_prefix} command #{index + 1} failed: #{command}") }
            all_succeeded = false
            return false if fail_fast
          end
        rescue StandardError => e
          non_interactive_output { print("Error executing #{phase} command #{index + 1}: #{e.message}") }
          logger.info { "Error: #{e.message}" }
          logger.info { output_separator }
          all_succeeded = false
          return false if fail_fast
        end
      end

      all_succeeded
    end
  end
end
