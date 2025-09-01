# frozen_string_literal: true

module ClaudeSwarm
  class ClaudeCodeExecutor < BaseExecutor
    def execute(prompt, options = {})
      # Log the request
      log_request(prompt)

      # Build SDK options
      sdk_options = build_sdk_options(prompt, options)

      # Variables to collect output
      all_messages = []
      result_response = nil

      # Execute with streaming
      begin
        ClaudeSDK.query(prompt, options: sdk_options) do |message|
          # Convert message to hash for logging
          message_hash = message_to_hash(message)
          all_messages << message_hash

          # Log streaming event BEFORE we modify anything
          log_streaming_event(message_hash)

          # Process specific message types
          case message
          when ClaudeSDK::Messages::System
            # Capture session_id from system init
            if message.subtype == "init" && message.data.is_a?(Hash)
              # For init messages, session_id is in the data hash
              session_id = message.data[:session_id] || message.data["session_id"]

              if session_id
                @session_id = session_id
                write_instance_state
              end
            end
          when ClaudeSDK::Messages::Assistant
            # Assistant messages only contain content blocks
            # No need to track for result extraction - result comes from Result message
          when ClaudeSDK::Messages::Result
            # Validate that we have actual result content
            if message.result.nil? || (message.result.is_a?(String) && message.result.strip.empty?)
              raise ExecutionError, "Claude SDK returned an empty result. The agent completed execution but provided no response content."
            end

            # Build result response in expected format
            result_response = {
              "type" => "result",
              "subtype" => message.subtype || "success",
              "cost_usd" => message.total_cost_usd,
              "is_error" => message.is_error || false,
              "duration_ms" => message.duration_ms,
              "result" => message.result, # Result text is directly in message.result
              "total_cost" => message.total_cost_usd,
              "session_id" => message.session_id,
            }
          end
        end
      rescue StandardError => e
        logger.error { "Execution error for #{@instance_name}: #{e.class} - #{e.message}" }
        logger.error { "Backtrace: #{e.backtrace.join("\n")}" }
        raise ExecutionError, "Claude Code execution failed: #{e.message}"
      end

      # Ensure we got a result
      raise ParseError, "No result found in SDK response" unless result_response

      # Write session JSON log
      all_messages.each do |msg|
        append_to_session_json(msg)
      end

      result_response
    rescue StandardError => e
      logger.error { "Unexpected error for #{@instance_name}: #{e.class} - #{e.message}" }
      logger.error { "Backtrace: #{e.backtrace.join("\n")}" }
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
        updated_at: Time.now.iso8601,
      }

      JsonHandler.write_file!(state_file, state_data)
      logger.info { "Wrote instance state for #{@instance_name} (#{@instance_id}) with session ID: #{@session_id}" }
    rescue StandardError => e
      logger.error { "Failed to write instance state for #{@instance_name} (#{@instance_id}): #{e.message}" }
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
      logger.debug { "SYSTEM: #{JsonHandler.pretty_generate!(event)}" }
    end

    def log_assistant_message(msg)
      # Assistant messages don't have stop_reason in SDK - they only have content
      content = msg["content"]
      logger.debug { "ASSISTANT: #{JsonHandler.pretty_generate!(content)}" } if content

      # Log tool calls
      tool_calls = content&.select { |c| c["type"] == "tool_use" } || []
      tool_calls.each do |tool_call|
        arguments = tool_call["input"].to_json
        arguments = "#{arguments[0..300]} ...}" if arguments.length > 300

        logger.info do
          "Tool call from #{instance_info} -> Tool: #{tool_call["name"]}, ID: #{tool_call["id"]}, Arguments: #{arguments}"
        end
      end

      # Log thinking text
      text = content&.select { |c| c["type"] == "text" } || []
      text.each do |t|
        logger.info { "#{instance_info} is thinking:\n---\n#{t["text"]}\n---" }
      end
    end

    def log_user_message(content)
      logger.debug { "USER: #{JsonHandler.pretty_generate!(content)}" }
    end

    def build_sdk_options(prompt, options)
      # Map CLI options to SDK options
      sdk_options = ClaudeSDK::ClaudeCodeOptions.new

      # Basic options
      # Only set model if ANTHROPIC_MODEL env var is not set
      sdk_options.model = @model if @model && !ENV["ANTHROPIC_MODEL"]
      sdk_options.cwd = @working_directory
      sdk_options.resume = @session_id if @session_id && !options[:new_session]

      # Permission mode
      if @vibe
        sdk_options.permission_mode = ClaudeSDK::PermissionMode::BYPASS_PERMISSIONS
      else
        # Build allowed tools list including MCP connections
        allowed_tools = options[:allowed_tools] ? Array(options[:allowed_tools]).dup : []

        # Add mcp__instance_name for each connection if we have instance info
        options[:connections]&.each do |connection_name|
          allowed_tools << "mcp__#{connection_name}"
        end

        # Set allowed and disallowed tools
        sdk_options.allowed_tools = allowed_tools if allowed_tools.any?
        sdk_options.disallowed_tools = Array(options[:disallowed_tools]) if options[:disallowed_tools]
      end

      # System prompt
      sdk_options.append_system_prompt = options[:system_prompt] if options[:system_prompt]

      # MCP configuration
      if @mcp_config
        sdk_options.mcp_servers = parse_mcp_config(@mcp_config)
      end

      # Handle additional directories by adding them to MCP servers
      if @additional_directories.any?
        setup_additional_directories_mcp(sdk_options)
      end

      # Add settings file path if it exists
      settings_file = File.join(@session_path, "#{@instance_name}_settings.json")
      sdk_options.settings = settings_file if File.exist?(settings_file)

      sdk_options
    end

    def parse_mcp_config(config_path)
      # Parse MCP JSON config file and convert to SDK format
      config = JsonHandler.parse_file!(config_path)
      mcp_servers = {}

      config["mcpServers"]&.each do |name, server_config|
        server_type = server_config["type"] || "stdio"

        mcp_servers[name] = case server_type
        when "stdio"
          ClaudeSDK::McpServerConfig::StdioServer.new(
            command: server_config["command"],
            args: server_config["args"] || [],
            env: server_config["env"] || {},
          )
        when "sse"
          ClaudeSDK::McpServerConfig::SSEServer.new(
            url: server_config["url"],
            headers: server_config["headers"] || {},
          )
        when "http"
          ClaudeSDK::McpServerConfig::HttpServer.new(
            url: server_config["url"],
            headers: server_config["headers"] || {},
          )
        else
          logger.warn { "Unsupported MCP server type: #{server_type} for server: #{name}" }
          nil
        end
      end

      mcp_servers.compact
    rescue StandardError => e
      logger.error { "Failed to parse MCP config: #{e.message}" }
      {}
    end

    def setup_additional_directories_mcp(sdk_options)
      # Workaround for --add-dir: add file system MCP servers for additional directories
      sdk_options.mcp_servers ||= {}

      @additional_directories.each do |dir|
        # This is a placeholder - the SDK doesn't directly support file system servers
        # You would need to implement a proper MCP server that provides file access
        logger.warn { "Additional directories not fully supported: #{dir}" }
      end
    end

    def message_to_hash(message)
      # Convert SDK message objects to hash format matching CLI JSON output
      case message
      when ClaudeSDK::Messages::System
        # System messages have subtype and data attributes
        # The data hash contains the actual information from the CLI
        hash = {
          "type" => "system",
          "subtype" => message.subtype,
        }

        # Include the data hash if it exists - this is where CLI puts info like session_id, tools, etc.
        if message.data.is_a?(Hash)
          # For "init" subtype, extract session_id and tools from data
          if message.subtype == "init"
            hash["session_id"] = message.data[:session_id] || message.data["session_id"]
            hash["tools"] = message.data[:tools] || message.data["tools"]
          end
          # You can add other relevant data fields as needed
        end

        hash.compact
      when ClaudeSDK::Messages::Assistant
        # Assistant messages only have content attribute
        {
          "type" => "assistant",
          "message" => {
            "type" => "message",
            "role" => "assistant",
            "content" => content_blocks_to_hash(message.content),
          },
          "session_id" => @session_id,
        }
      when ClaudeSDK::Messages::User
        # User messages only have content attribute (a string)
        {
          "type" => "user",
          "message" => {
            "type" => "message",
            "role" => "user",
            "content" => message.content,
          },
          "session_id" => @session_id,
        }
      when ClaudeSDK::Messages::Result
        # Result messages have multiple attributes
        {
          "type" => "result",
          "subtype" => message.subtype || "success",
          "cost_usd" => message.total_cost_usd,
          "is_error" => message.is_error || false,
          "duration_ms" => message.duration_ms,
          "duration_api_ms" => message.duration_api_ms,
          "num_turns" => message.num_turns,
          "result" => message.result, # Result text is in message.result, not from content
          "total_cost" => message.total_cost_usd,
          "total_cost_usd" => message.total_cost_usd,
          "session_id" => message.session_id,
          "usage" => message.usage,
        }.compact
      else
        # Fallback for unknown message types
        begin
          message.to_h
        rescue
          { "type" => "unknown", "data" => message.to_s }
        end
      end
    end

    def content_blocks_to_hash(content)
      return [] unless content

      content.map do |block|
        case block
        when ClaudeSDK::ContentBlock::Text
          { "type" => "text", "text" => block.text }
        when ClaudeSDK::ContentBlock::ToolUse
          {
            "type" => "tool_use",
            "id" => block.id,
            "name" => block.name,
            "input" => block.input,
          }
        when ClaudeSDK::ContentBlock::ToolResult
          {
            "type" => "tool_result",
            "tool_use_id" => block.tool_use_id,
            "content" => block.content,
            "is_error" => block.is_error,
          }
        else
          # Fallback
          begin
            block.to_h
          rescue
            { "type" => "unknown", "data" => block.to_s }
          end
        end
      end
    end
  end
end
