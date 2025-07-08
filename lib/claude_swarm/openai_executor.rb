# frozen_string_literal: true

module ClaudeSwarm
  class OpenAIExecutor
    attr_reader :session_id, :last_response, :working_directory, :logger, :session_path

    def initialize(working_directory: Dir.pwd, model: nil, mcp_config: nil, vibe: false,
      instance_name: nil, instance_id: nil, calling_instance: nil, calling_instance_id: nil,
      claude_session_id: nil, additional_directories: [],
      temperature: 0.3, api_version: "chat_completion", openai_token_env: "OPENAI_API_KEY",
      base_url: nil, reasoning_effort: nil)
      @working_directory = working_directory
      @additional_directories = additional_directories
      @model = model
      @mcp_config = mcp_config
      @vibe = vibe
      @session_id = claude_session_id
      @last_response = nil
      @instance_name = instance_name
      @instance_id = instance_id
      @calling_instance = calling_instance
      @calling_instance_id = calling_instance_id
      @temperature = temperature
      @api_version = api_version
      @base_url = base_url
      @reasoning_effort = reasoning_effort

      # Conversation state for maintaining context
      @conversation_messages = []
      @previous_response_id = nil

      # Setup logging first
      setup_logging

      # Setup OpenAI client
      setup_openai_client(openai_token_env)

      # Setup MCP client for tools
      setup_mcp_client

      # Create API handlers
      @chat_completion_handler = OpenAIChatCompletion.new(
        openai_client: @openai_client,
        mcp_client: @mcp_client,
        available_tools: @available_tools,
        logger: self,
        instance_name: @instance_name,
        model: @model,
        temperature: @temperature,
        reasoning_effort: @reasoning_effort,
      )

      @responses_handler = OpenAIResponses.new(
        openai_client: @openai_client,
        mcp_client: @mcp_client,
        available_tools: @available_tools,
        logger: self,
        instance_name: @instance_name,
        model: @model,
        temperature: @temperature,
        reasoning_effort: @reasoning_effort,
      )
    end

    def execute(prompt, options = {})
      # Log the request
      log_request(prompt)

      # Start timing
      start_time = Time.now

      # Execute based on API version
      result = if @api_version == "responses"
        @responses_handler.execute(prompt, options)
      else
        @chat_completion_handler.execute(prompt, options)
      end

      # Calculate duration
      duration_ms = ((Time.now - start_time) * 1000).round

      # Format response similar to ClaudeCodeExecutor
      response = {
        "type" => "result",
        "result" => result,
        "duration_ms" => duration_ms,
        "total_cost" => calculate_cost(result),
        "session_id" => @session_id,
      }

      log_response(response)

      @last_response = response
      response
    rescue StandardError => e
      @logger.error("Unexpected error for #{@instance_name}: #{e.class} - #{e.message}")
      @logger.error("Backtrace: #{e.backtrace.join("\n")}")
      raise
    end

    def reset_session
      @session_id = nil
      @last_response = nil
      @chat_completion_handler&.reset_session
      @responses_handler&.reset_session
    end

    def has_session?
      !@session_id.nil?
    end

    # Delegate logger methods for the API handlers
    def info(message)
      @logger.info(message)
    end

    def error(message)
      @logger.error(message)
    end

    def warn(message)
      @logger.warn(message)
    end

    def debug(message)
      @logger.debug(message)
    end

    # Session JSON logger for the API handlers
    def session_json_logger
      self
    end

    def log(event)
      append_to_session_json(event)
    end

    private

    def setup_openai_client(token_env)
      config = {
        access_token: ENV.fetch(token_env),
        log_errors: true,
        request_timeout: 1800, # 30 minutes
      }
      config[:uri_base] = @base_url if @base_url

      @openai_client = OpenAI::Client.new(config)
    rescue KeyError
      raise ExecutionError, "OpenAI API key not found in environment variable: #{token_env}"
    end

    def setup_mcp_client
      return unless @mcp_config && File.exist?(@mcp_config)

      # Read MCP config to find MCP servers
      mcp_data = JSON.parse(File.read(@mcp_config))

      # Create MCP client with all MCP servers from the config
      if mcp_data["mcpServers"] && !mcp_data["mcpServers"].empty?
        mcp_configs = []

        mcp_data["mcpServers"].each do |name, server_config|
          case server_config["type"]
          when "stdio"
            # Combine command and args into a single array
            command_array = [server_config["command"]]
            command_array.concat(server_config["args"] || [])

            mcp_configs << MCPClient.stdio_config(
              command: command_array,
              name: name,
            )
          when "sse"
            @logger.warn("SSE MCP servers not yet supported for OpenAI instances: #{name}")
            # TODO: Add SSE support when available in ruby-mcp-client
          end
        end

        if mcp_configs.any?
          @mcp_client = MCPClient.create_client(
            mcp_server_configs: mcp_configs,
            logger: @logger,
          )

          # List available tools from all MCP servers
          begin
            @available_tools = @mcp_client.list_tools
            @logger.info("Loaded #{@available_tools.size} tools from #{mcp_configs.size} MCP server(s)")
          rescue StandardError => e
            @logger.error("Failed to load MCP tools: #{e.message}")
            @available_tools = []
          end
        end
      end
    rescue StandardError => e
      @logger.error("Failed to setup MCP client: #{e.message}")
      @mcp_client = nil
      @available_tools = []
    end

    def calculate_cost(_result)
      # Simplified cost calculation
      # In reality, we'd need to track token usage
      "$0.00"
    end

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

      return unless @instance_name

      instance_info = @instance_name
      instance_info += " (#{@instance_id})" if @instance_id
      @logger.info("Started OpenAI executor for instance: #{instance_info}")
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
        timestamp: Time.now.iso8601,
      }

      append_to_session_json(event)
    end

    def log_response(response)
      caller_info = @calling_instance
      caller_info += " (#{@calling_instance_id})" if @calling_instance_id
      instance_info = @instance_name
      instance_info += " (#{@instance_id})" if @instance_id
      @logger.info(
        "(#{response["total_cost"]} - #{response["duration_ms"]}ms) #{instance_info} -> #{caller_info}: \n---\n#{response["result"]}\n---",
      )
    end

    def log_streaming_content(content)
      # Log streaming content similar to ClaudeCodeExecutor
      instance_info = @instance_name
      instance_info += " (#{@instance_id})" if @instance_id
      @logger.debug("#{instance_info} streaming: #{content}")
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
          instance_id: @instance_id,
          calling_instance: @calling_instance,
          calling_instance_id: @calling_instance_id,
          timestamp: Time.now.iso8601,
          event: event,
        }

        # Write as single line JSON (JSONL format)
        file.puts(entry.to_json)

        file.flock(File::LOCK_UN)
      end
    rescue StandardError => e
      @logger.error("Failed to append to session JSON: #{e.message}")
      raise
    end

    class ExecutionError < StandardError; end
  end
end
