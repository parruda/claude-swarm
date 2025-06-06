# frozen_string_literal: true

require "json"
require "open3"
require "logger"
require "fileutils"
require_relative "session_path"

module ClaudeSwarm
  class ClaudeCodeExecutor
    attr_reader :session_id, :last_response, :working_directory, :logger, :session_path

    def initialize(working_directory: Dir.pwd, model: nil, mcp_config: nil, vibe: false, instance_name: nil, calling_instance: nil)
      @working_directory = working_directory
      @model = model
      @mcp_config = mcp_config
      @vibe = vibe
      @session_id = nil
      @last_response = nil
      @instance_name = instance_name
      @calling_instance = calling_instance

      # Setup logging
      setup_logging
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
          @session_id = json_data["session_id"] if json_data["type"] == "system" && json_data["subtype"] == "init"

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

    def reset_session
      @session_id = nil
      @last_response = nil
    end

    def has_session?
      !@session_id.nil?
    end

    private

    def setup_logging
      # Use session path from environment (required)
      @session_path = SessionPath.from_env
      SessionPath.ensure_directory(@session_path)

      # Create logger with session.log filename
      log_filename = "session.log"
      log_path = File.join(@session_path, log_filename)
      @logger = Logger.new(log_path)
      @logger.level = Logger::INFO

      # Custom formatter for better readability
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S.%L")}] [#{severity}] #{msg}\n"
      end

      @logger.info("Started Claude Code executor for instance: #{@instance_name}") if @instance_name
    end

    def log_request(prompt)
      @logger.info("#{@calling_instance} -> #{@instance_name}: \n---\n#{prompt}\n---")
      
      # Also log to JSON for complete audit trail
      request_event = {
        type: "instance_request",
        message: {
          role: "user",
          content: prompt
        }
      }
      append_to_session_json(request_event)
    end

    def log_response(response)
      @logger.info(
        "($#{response["total_cost"]} - #{response["duration_ms"]}ms) #{@instance_name} -> #{@calling_instance}: \n---\n#{response["result"]}\n---"
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

        @logger.info(
          "Tool call from #{@instance_name} -> Tool: #{tool_call["name"]}, ID: #{tool_call["id"]}, Arguments: #{arguments}"
        )
      end

      text = content.select { |c| c["type"] == "text" }
      text.each do |t|
        @logger.info("#{@instance_name} is thinking:\n---\n#{t["text"]}\n---")
      end
    end

    def log_user_message(content)
      @logger.debug("USER: #{JSON.pretty_generate(content)}")
    end

    def append_to_session_json(event)
      json_filename = "session.log.json"
      json_path = File.join(@session_path, json_filename)

      # Use file locking to ensure thread-safe writes
      File.open(json_path, File::WRONLY | File::APPEND | File::CREAT) do |file|
        file.flock(File::LOCK_EX)

        # Create entry with metadata
        entry = {
          instance: @instance_name,
          calling_instance: @calling_instance,
          timestamp: Time.now.iso8601,
          event: event
        }

        # Write as single line JSON (JSONL format)
        file.puts(entry.to_json)

        file.flock(File::LOCK_UN)
      end
    rescue StandardError => e
      @logger.error("Failed to append to session JSON: #{e.message}")
      raise
    end

    def build_command_array(prompt, options)
      cmd_array = ["claude"]

      # Add model if specified
      cmd_array += ["--model", @model]

      cmd_array << "--verbose"

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
        # Add allowed tools if any
        if options[:allowed_tools]
          tools = Array(options[:allowed_tools]).join(",")
          cmd_array += ["--allowedTools", tools]
        end

        # Add disallowed tools if any
        if options[:disallowed_tools]
          disallowed_tools = Array(options[:disallowed_tools]).join(",")
          cmd_array += ["--disallowedTools", disallowed_tools]
        end

        # Add permission prompt tool if not in vibe mode
        cmd_array += ["--permission-prompt-tool", "mcp__permissions__check_permission"]
      end

      cmd_array
    end

    class ExecutionError < StandardError; end
    class ParseError < StandardError; end
  end
end
