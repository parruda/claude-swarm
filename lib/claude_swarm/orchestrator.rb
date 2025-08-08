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
      @provided_session_id = session_id
      # Store worktree option for later use
      @worktree_option = worktree
      @needs_worktree_manager = worktree.is_a?(String) || worktree == "" ||
        configuration.instances.values.any? { |inst| !inst[:worktree].nil? }
      # Store modified instances after worktree setup
      @modified_instances = nil
      # Track start time for runtime calculation
      @start_time = nil
      # Track transcript tailing thread
      @transcript_thread = nil

      # Set environment variable for prompt mode to suppress output
      ENV["CLAUDE_SWARM_PROMPT"] = "1" if @non_interactive_prompt

      # Initialize session path
      if @restore_session_path
        # Use existing session path for restoration
        @session_path = @restore_session_path
        @session_log_path = File.join(@session_path, "session.log")
      else
        # Generate new session path
        session_params = { working_dir: ClaudeSwarm.root_dir }
        session_params[:session_id] = @provided_session_id if @provided_session_id
        @session_path = SessionPath.generate(**session_params)
        SessionPath.ensure_directory(@session_path)
        @session_log_path = File.join(@session_path, "session.log")

        # Extract session ID from path (the timestamp part)
        @session_id = File.basename(@session_path)

      end
      ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path
      ENV["CLAUDE_SWARM_ROOT_DIR"] = ClaudeSwarm.root_dir

      # Initialize components that depend on session path
      @process_tracker = ProcessTracker.new(@session_path)
      @settings_generator = SettingsGenerator.new(@config)

      # Initialize WorktreeManager if needed
      if @needs_worktree_manager && !@restore_session_path
        cli_option = @worktree_option.is_a?(String) && !@worktree_option.empty? ? @worktree_option : nil
        @worktree_manager = WorktreeManager.new(cli_option, session_id: @session_id)
      end
    end

    def start
      # Track start time
      @start_time = Time.now

      begin
        start_internal
      rescue StandardError => e
        # Ensure cleanup happens even on unexpected errors
        cleanup_processes
        cleanup_run_symlink
        cleanup_worktrees
        raise e
      end
    end

    private

    def start_internal
      if @restore_session_path
        non_interactive_output do
          puts "🔄 Restoring Claude Swarm: #{@config.swarm_name}"
          puts "😎 Vibe mode ON" if @vibe
        end

        # Create run symlink for restored session
        create_run_symlink

        non_interactive_output do
          puts "📝 Using existing session: #{@session_path}/"
        end

        # Check if the original session used worktrees
        restore_worktrees_if_needed(@session_path)

        # Regenerate MCP configurations with session IDs for restoration
        @generator.generate_all
        non_interactive_output do
          puts "✓ Regenerated MCP configurations with session IDs"
        end

        # Generate settings files
        @settings_generator.generate_all
        non_interactive_output do
          puts "✓ Generated settings files with hooks"
        end
      else
        non_interactive_output do
          puts "🐝 Starting Claude Swarm: #{@config.swarm_name}"
          puts "😎 Vibe mode ON" if @vibe
        end

        # Create run symlink for new session
        create_run_symlink

        non_interactive_output do
          puts "📝 Session files will be saved to: #{@session_path}/"
        end

        # Setup worktrees if needed
        if @worktree_manager
          begin
            non_interactive_output { print("🌳 Setting up Git worktrees...") }

            # Get all instances for worktree setup
            # Note: instances.values already includes the main instance
            all_instances = @config.instances.values

            @worktree_manager.setup_worktrees(all_instances)

            non_interactive_output do
              puts "✓ Worktrees created with branch: #{@worktree_manager.worktree_name}"
            end
          rescue StandardError => e
            non_interactive_output { print("❌ Failed to setup worktrees: #{e.message}") }
            cleanup_processes
            cleanup_run_symlink
            cleanup_worktrees
            raise
          end
        end

        # Generate all MCP configuration files
        @generator.generate_all
        non_interactive_output do
          puts "✓ Generated MCP configurations in session directory"
        end

        # Generate settings files
        @settings_generator.generate_all
        non_interactive_output do
          puts "✓ Generated settings files with hooks"
        end

        # Save swarm config path for restoration
        save_swarm_config_path(@session_path)
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

      # Start transcript tailing thread for main instance
      @transcript_thread = start_transcript_tailing

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

          # Validate directories after before commands have run
          begin
            @config.validate_directories
            non_interactive_output do
              puts "✓ All directories validated successfully"
            end
          rescue ClaudeSwarm::Error => e
            non_interactive_output { print("❌ Directory validation failed: #{e.message}") }
            cleanup_processes
            cleanup_run_symlink
            cleanup_worktrees
            exit(1)
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

      # Clean up transcript tailing thread
      cleanup_transcript_thread

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
      cleanup_transcript_thread
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

      # Add settings file if it exists for the main instance
      settings_file = @settings_generator.settings_path(@config.main_instance)
      if File.exist?(settings_file)
        parts << "--settings"
        parts << settings_file
      end

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
          logger.info { line.chomp }
        end

        wait_thr.value
      end
    end

    def start_transcript_tailing
      Thread.new do
        path_file = File.join(@session_path, "main_instance_transcript.path")

        # Wait for path file to exist (created by SessionStart hook)
        sleep(0.5) until File.exist?(path_file)

        # Read the transcript path
        transcript_path = File.read(path_file).strip

        # Wait for transcript file to exist
        sleep(0.5) until File.exist?(transcript_path)

        # Tail the transcript file continuously (like tail -f)
        File.open(transcript_path, "r") do |file|
          # Start from the beginning to capture all entries
          file.seek(0, IO::SEEK_SET) # Start at beginning of file

          loop do
            line = file.gets
            if line
              begin
                # Parse JSONL entry
                transcript_entry = JSON.parse(line)

                # Skip summary entries - these are just conversation titles
                next if transcript_entry["type"] == "summary"

                # Convert to session.log.json format
                session_entry = convert_transcript_to_session_format(transcript_entry)

                # Only write if we got a valid conversion (skips summary and other non-relevant entries)
                if session_entry
                  # Write with file locking (same pattern as BaseExecutor)
                  session_json_path = File.join(@session_path, "session.log.json")
                  File.open(session_json_path, File::WRONLY | File::APPEND | File::CREAT) do |log_file|
                    log_file.flock(File::LOCK_EX)
                    log_file.puts(session_entry.to_json)
                  end
                end
              rescue JSON::ParserError
                # Silently skip unparseable lines
              rescue StandardError
                # Silently handle other errors to keep thread running
              end
            else
              # No new data, sleep briefly
              sleep(0.1)
            end
          end
        end
      rescue StandardError
        # Silently handle thread errors
      end
    end

    def convert_transcript_to_session_format(transcript_entry)
      # Skip if no type
      return unless transcript_entry["type"]

      instance_name = @config.main_instance
      instance_id = "main"
      timestamp = transcript_entry["timestamp"] || Time.now.iso8601

      case transcript_entry["type"]
      when "user"
        # User message - format as request from user to main instance
        message = transcript_entry["message"]

        # Extract prompt text - message might be a string or an object
        prompt_text = if message.is_a?(String)
          message
        elsif message.is_a?(Hash)
          content = message["content"]
          if content.is_a?(String)
            content
          elsif content.is_a?(Array)
            # For tool results or complex content, extract text
            extract_text_from_array(content)
          else
            ""
          end
        else
          ""
        end

        {
          instance: instance_name,
          instance_id: instance_id,
          timestamp: timestamp,
          event: {
            type: "request",
            from_instance: "user",
            from_instance_id: "user",
            to_instance: instance_name,
            to_instance_id: instance_id,
            prompt: prompt_text,
            timestamp: timestamp,
          },
        }
      when "assistant"
        # Assistant message - format as assistant response
        message = transcript_entry["message"]

        # Build a clean message structure without transcript-specific fields
        clean_message = {
          "type" => "message",
          "role" => "assistant",
        }

        # Handle different message formats
        if message.is_a?(String)
          # Simple string message
          clean_message["content"] = [{ "type" => "text", "text" => message }]
        elsif message.is_a?(Hash)
          # Only include the fields that other instances include
          clean_message["content"] = message["content"] if message["content"]
          clean_message["model"] = message["model"] if message["model"]
          clean_message["usage"] = message["usage"] if message["usage"]
        end

        {
          instance: instance_name,
          instance_id: instance_id,
          timestamp: timestamp,
          event: {
            type: "assistant",
            message: clean_message,
            session_id: transcript_entry["sessionId"],
          },
        }
      end
      # For other types (like summary), return nil to skip them
    end

    def extract_text_from_array(content)
      content.map do |item|
        if item.is_a?(Hash)
          item["text"] || item["content"] || ""
        else
          item.to_s
        end
      end.join("\n")
    end

    def cleanup_transcript_thread
      return unless @transcript_thread

      @transcript_thread.terminate if @transcript_thread.alive?
      @transcript_thread.join(1) # Wait up to 1 second for thread to finish
    rescue StandardError => e
      logger.error { "Error cleaning up transcript thread: #{e.message}" }
    end

    def logger
      @logger ||= Logger.new(File.join(@session_path, "session.log"), level: :info, progname: "orchestrator")
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
