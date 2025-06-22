# frozen_string_literal: true

require "json"
require "open3"

module ClaudeSwarm
  class ClaudeCodeExecutor < BaseExecutor
    def initialize(working_directory: Dir.pwd, model: nil, mcp_config: nil, vibe: false,
                   instance_name: nil, instance_id: nil, calling_instance: nil, calling_instance_id: nil,
                   claude_session_id: nil, additional_directories: [])
      # Call parent constructor with common parameters
      super(
        working_directory: working_directory,
        instance_name: instance_name,
        instance_id: instance_id,
        calling_instance: calling_instance,
        calling_instance_id: calling_instance_id,
        session_id: claude_session_id
      )

      # Initialize Claude-specific attributes
      @additional_directories = additional_directories
      @model = model
      @mcp_config = mcp_config
      @vibe = vibe
    end

    def execute(prompt, options = {})
      # Log the request
      log_request(prompt)

      cmd_array = build_command_array(prompt, options)

      # Variables to collect output
      stderr_output = []
      result_response = nil

      # Execute command with streaming
      Open3.popen3(*cmd_array, chdir: @working_directory) do |stdin, stdout, stderr, wait_thread|
        stdin.close

        # Read stderr in a separate thread
        stderr_thread = Thread.new do
          stderr.each_line { |line| stderr_output << line }
        end

        # Process stdout line by line
        stdout.each_line do |line|
          json_data = JSON.parse(line.strip)

          # Log each JSON event
          log_streaming_event(json_data)

          # Capture session_id from system init
          if json_data["type"] == "system" && json_data["subtype"] == "init"
            @session_id = json_data["session_id"]
            write_instance_state
          end

          # Capture the final result
          result_response = json_data if json_data["type"] == "result"
        rescue JSON::ParserError => e
          @logger.warn("Failed to parse JSON line: #{line.strip} - #{e.message}")
        end

        # Wait for stderr thread to finish
        stderr_thread.join

        # Check exit status
        exit_status = wait_thread.value
        unless exit_status.success?
          error_msg = stderr_output.join
          @logger.error("Execution error for #{@instance_name}: #{error_msg}")
          raise ExecutionError, "Claude Code execution failed: #{error_msg}"
        end
      end

      # Ensure we got a result
      raise ParseError, "No result found in stream output" unless result_response

      result_response
    rescue StandardError => e
      @logger.error("Unexpected error for #{@instance_name}: #{e.class} - #{e.message}")
      @logger.error("Backtrace: #{e.backtrace.join("\n")}")
      raise
    end

    private

    def write_instance_state
      return unless @instance_id && @session_id

      state_dir = File.join(@session_path, "state")
      FileUtils.mkdir_p(state_dir)

      state_file = File.join(state_dir, "#{@instance_id}.json")
      state_data = {
        instance_name: @instance_name,
        instance_id: @instance_id,
        claude_session_id: @session_id,
        status: "active",
        updated_at: Time.now.iso8601
      }

      File.write(state_file, JSON.pretty_generate(state_data))
      @logger.info("Wrote instance state for #{@instance_name} (#{@instance_id}) with session ID: #{@session_id}")
    rescue StandardError => e
      @logger.error("Failed to write instance state for #{@instance_name} (#{@instance_id}): #{e.message}")
    end

    def log_request(prompt)
      caller_info = @calling_instance
      caller_info += " (#{@calling_instance_id})" if @calling_instance_id
      instance_info = @instance_name
      instance_info += " (#{@instance_id})" if @instance_id
      @logger.info("#{caller_info} -> #{instance_info}: \n---\n#{prompt}\n---")

      # Build event hash for JSON logging
      event = {
        type: "request",
        from_instance: @calling_instance,
        from_instance_id: @calling_instance_id,
        to_instance: @instance_name,
        to_instance_id: @instance_id,
        prompt: prompt,
        timestamp: Time.now.iso8601
      }

      append_to_session_json(event)
    end

    def log_response(response)
      caller_info = @calling_instance
      caller_info += " (#{@calling_instance_id})" if @calling_instance_id
      instance_info = @instance_name
      instance_info += " (#{@instance_id})" if @instance_id
      @logger.info(
        "($#{response["total_cost"]} - #{response["duration_ms"]}ms) #{instance_info} -> #{caller_info}: \n---\n#{response["result"]}\n---"
      )
    end

    def log_streaming_event(event)
      append_to_session_json(event)

      return log_system_message(event) if event["type"] == "system"

      # Add specific details based on event type
      case event["type"]
      when "assistant"
        log_assistant_message(event["message"])
      when "user"
        log_user_message(event["message"]["content"])
      when "result"
        log_response(event)
      end
    end

    def log_system_message(event)
      @logger.debug("SYSTEM: #{JSON.pretty_generate(event)}")
    end

    def log_assistant_message(msg)
      return if msg["stop_reason"] == "end_turn" # that means it is not a thought but the final answer

      content = msg["content"]
      @logger.debug("ASSISTANT: #{JSON.pretty_generate(content)}")
      tool_calls = content.select { |c| c["type"] == "tool_use" }
      tool_calls.each do |tool_call|
        arguments = tool_call["input"].to_json
        arguments = "#{arguments[0..300]} ...}" if arguments.length > 300

        instance_info = @instance_name
        instance_info += " (#{@instance_id})" if @instance_id
        @logger.info(
          "Tool call from #{instance_info} -> Tool: #{tool_call["name"]}, ID: #{tool_call["id"]}, Arguments: #{arguments}"
        )
      end

      text = content.select { |c| c["type"] == "text" }
      text.each do |t|
        instance_info = @instance_name
        instance_info += " (#{@instance_id})" if @instance_id
        @logger.info("#{instance_info} is thinking:\n---\n#{t["text"]}\n---")
      end
    end

    def log_user_message(content)
      @logger.debug("USER: #{JSON.pretty_generate(content)}")
    end

    def build_command_array(prompt, options)
      cmd_array = ["claude"]

      # Add model if specified
      cmd_array += ["--model", @model]

      cmd_array << "--verbose"

      # Add additional directories with --add-dir
      cmd_array << "--add-dir" if @additional_directories.any?
      @additional_directories.each do |additional_dir|
        cmd_array << additional_dir
      end

      # Add MCP config if specified
      cmd_array += ["--mcp-config", @mcp_config] if @mcp_config

      # Resume session if we have a session ID
      cmd_array += ["--resume", @session_id] if @session_id && !options[:new_session]

      # Always use JSON output format for structured responses
      cmd_array += ["--output-format", "stream-json"]

      # Add non-interactive mode with prompt
      cmd_array += ["--print", "-p", prompt]

      # Add any custom system prompt
      cmd_array += ["--append-system-prompt", options[:system_prompt]] if options[:system_prompt]

      # Add any allowed tools or vibe flag
      if @vibe
        cmd_array << "--dangerously-skip-permissions"
      else
        # Build allowed tools list including MCP connections
        allowed_tools = options[:allowed_tools] ? Array(options[:allowed_tools]).dup : []

        # Add mcp__instance_name for each connection if we have instance info
        options[:connections]&.each do |connection_name|
          allowed_tools << "mcp__#{connection_name}"
        end

        # Add allowed tools if any
        if allowed_tools.any?
          tools_str = allowed_tools.join(",")
          cmd_array += ["--allowedTools", tools_str]
        end

        # Add disallowed tools if any
        if options[:disallowed_tools]
          disallowed_tools = Array(options[:disallowed_tools]).join(",")
          cmd_array += ["--disallowedTools", disallowed_tools]
        end
      end

      cmd_array
    end
  end
end
