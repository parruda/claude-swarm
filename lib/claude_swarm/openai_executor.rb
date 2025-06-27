# frozen_string_literal: true

require "json"
require "logger"
require "fileutils"
require "openai"
require "mcp_client"
require "securerandom"

module ClaudeSwarm
  class OpenAIExecutor
    attr_reader :session_id, :last_response, :working_directory, :logger, :session_path

    def initialize(working_directory: Dir.pwd, model: nil, mcp_config: nil, vibe: false,
                   instance_name: nil, instance_id: nil, calling_instance: nil, calling_instance_id: nil,
                   claude_session_id: nil, additional_directories: [],
                   temperature: 0.3, api_version: "chat_completion", openai_token_env: "OPENAI_API_KEY",
                   base_url: nil)
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

      # Conversation state for maintaining context
      @conversation_messages = []
      @previous_response_id = nil

      # Setup logging first
      setup_logging

      # Setup OpenAI client
      setup_openai_client(openai_token_env)

      # Setup MCP client for tools
      setup_mcp_client
    end

    def execute(prompt, options = {})
      # Log the request
      log_request(prompt)

      # Start timing
      start_time = Time.now

      # Execute based on API version
      result = if @api_version == "responses"
                 execute_responses_api(prompt, options)
               else
                 execute_chat_api(prompt, options)
               end

      # Calculate duration
      duration_ms = ((Time.now - start_time) * 1000).round

      # Format response similar to ClaudeCodeExecutor
      response = {
        "type" => "result",
        "result" => result,
        "duration_ms" => duration_ms,
        "total_cost" => calculate_cost(result),
        "session_id" => @session_id
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
      @conversation_messages = []
      @previous_response_id = nil
    end

    def has_session?
      !@session_id.nil?
    end

    private

    def convert_tools_to_openai_format
      return [] unless @available_tools

      @available_tools.map do |tool|
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: tool.schema || {}
          }
        }
      end
    end

    def setup_openai_client(token_env)
      config = {
        access_token: ENV.fetch(token_env),
        log_errors: true
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
              name: name
            )
          when "sse"
            @logger.warn("SSE MCP servers not yet supported for OpenAI instances: #{name}")
            # TODO: Add SSE support when available in ruby-mcp-client
          end
        end

        if mcp_configs.any?
          @mcp_client = MCPClient.create_client(
            mcp_server_configs: mcp_configs,
            logger: @logger
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

    def execute_chat_api(prompt, options)
      # Build messages array
      messages = build_messages(prompt, options)

      # Build parameters
      parameters = {
        model: @model,
        messages: messages,
        temperature: @temperature
      }

      # Add tools if available
      if @available_tools&.any? && @mcp_client
        begin
          parameters[:tools] = @mcp_client.to_openai_tools
        rescue NoMethodError
          @logger.warn("to_openai_tools method not available, converting manually")
          parameters[:tools] = convert_tools_to_openai_format
        end
      end

      # Make the API call without streaming
      response = @openai_client.chat(parameters: parameters)

      # Extract the message from the response
      message = response.dig("choices", 0, "message")
      
      if message.nil?
        @logger.error("No message in response: #{response.inspect}")
        return "Error: No response from OpenAI"
      end

      # Check if there are tool calls
      if message["tool_calls"]
        # Handle tool calls
        handle_tool_calls(message["tool_calls"], messages)
      else
        # Regular text response
        response_text = message["content"] || ""
        messages << { role: "assistant", content: response_text }
        @conversation_messages = messages
        response_text
      end
    end

    def execute_responses_api(prompt, _options)
      # Build parameters
      parameters = {
        model: @model,
        input: prompt
      }

      # Add previous response ID for conversation continuity
      parameters[:previous_response_id] = @previous_response_id if @previous_response_id

      # Add tools if available
      if @available_tools&.any?
        # Convert tools to responses API format
        parameters[:tools] = @available_tools.map do |tool|
          {
            "type" => "function",
            "name" => tool.name,
            "description" => tool.description,
            "parameters" => tool.schema || {}
          }
        end
        @logger.info("Available tools for responses API: #{parameters[:tools].map { |t| t["name"] }.join(", ")}")
      else
        @logger.warn("No tools available for responses API")
      end

      # Make the API call without streaming
      begin
        response = @openai_client.responses.create(parameters: parameters)
      rescue StandardError => e
        @logger.error("Responses API error: #{e.class} - #{e.message}")
        @logger.error("Request parameters: #{parameters.inspect}")
        return "Error calling OpenAI responses API: #{e.message}"
      end

      # Log the full response for debugging
      @logger.info("Responses API response: #{response.inspect}")

      # Extract response details
      response_id = response["id"]
      
      # Store response ID for next conversation turn
      @previous_response_id = response_id if response_id

      # Handle response based on output structure
      output = response["output"]
      
      if output.nil?
        @logger.error("No output in response")
        return "Error: No output in OpenAI response"
      end

      # Check if output is an array (as per ruby-openai expert)
      if output.is_a?(Array) && !output.empty?
        first_output = output.first
        @logger.info("First output item: #{first_output.inspect}")
        
        # Check if it's a function call
        if first_output["type"] == "function_call"
          # Tool call response
          tool_calls = output.map do |item|
            if item["type"] == "function_call" && item["function"]
              {
                "id" => item["id"] || SecureRandom.uuid,
                "function" => {
                  "name" => item["function"]["name"],
                  "arguments" => item["function"]["arguments"] || "{}"
                }
              }
            end
          end.compact
          
          if tool_calls.empty?
            @logger.error("No valid tool calls found in response")
            return "Error: Invalid tool call format in response"
          end
          
          # Execute tools and continue
          execute_tools_and_continue(tool_calls, prompt)
        elsif first_output["content"]
          # Text response - extract text from content array
          content_items = first_output["content"]
          if content_items.is_a?(Array)
            text_content = content_items.find { |item| item["text"] }
            text_content ? text_content["text"] : ""
          else
            ""
          end
        else
          @logger.error("Unknown output structure: #{first_output.inspect}")
          "Error: Unknown response structure"
        end
      else
        @logger.error("Unexpected output format: #{output.inspect}")
        "Error: Unexpected response format"
      end
    end

    def build_messages(prompt, options)
      messages = []

      # Add system prompt if provided
      system_prompt = options[:system_prompt] || @prompt
      if system_prompt && @conversation_messages.empty?
        messages << { role: "system", content: system_prompt }
      elsif !@conversation_messages.empty?
        # Use existing conversation
        messages = @conversation_messages.dup
      end

      # Add user message
      messages << { role: "user", content: prompt }

      messages
    end

    def handle_tool_calls(tool_calls, messages)
      # Add the assistant message with tool calls
      messages << {
        role: "assistant",
        content: nil,
        tool_calls: tool_calls
      }

      # Execute each tool and collect results
      tool_calls.each do |tool_call|
        tool_name = tool_call.dig("function", "name")
        tool_args_str = tool_call.dig("function", "arguments")

        begin
          # Parse arguments
          tool_args = tool_args_str.is_a?(String) ? JSON.parse(tool_args_str) : tool_args_str
          
          # Execute tool via MCP
          @logger.info("Executing tool: #{tool_name} with args: #{tool_args.inspect}")
          result = @mcp_client.call_tool(tool_name, tool_args)
          
          # Add tool result to messages
          messages << {
            tool_call_id: tool_call["id"],
            role: "tool",
            name: tool_name,
            content: result.to_s
          }
        rescue StandardError => e
          @logger.error("Tool execution failed for #{tool_name}: #{e.message}")
          @logger.error(e.backtrace.join("\n"))
          
          # Add error as tool result
          messages << {
            tool_call_id: tool_call["id"],
            role: "tool",
            name: tool_name,
            content: "Error: #{e.message}"
          }
        end
      end

      # Make another call to get the final response with tool results
      final_response = @openai_client.chat(
        parameters: {
          model: @model,
          messages: messages,
          temperature: @temperature
        }
      )

      final_message = final_response.dig("choices", 0, "message")
      if final_message
        final_text = final_message["content"] || ""
        messages << { role: "assistant", content: final_text }
        @conversation_messages = messages
        final_text
      else
        @logger.error("No final message in tool response: #{final_response.inspect}")
        "Error: Failed to get response after tool execution"
      end
    end

    def execute_tools_and_continue(tool_calls, original_prompt)
      # Execute tools via MCP
      tool_outputs = []

      tool_calls.each do |tool_call|
        tool_name = tool_call.dig("function", "name")
        tool_args = tool_call.dig("function", "arguments")

        begin
          # Execute tool via MCP
          result = @mcp_client.call_tool(tool_name, JSON.parse(tool_args))
          tool_outputs << "Tool: #{tool_name}\nResult: #{result}"
          @logger.info("Executed tool #{tool_name}: #{result}")
        rescue StandardError => e
          @logger.error("Tool execution failed: #{e.message}")
          tool_outputs << "Tool: #{tool_name}\nError: #{e.message}"
        end
      end

      # Format the combined prompt with tool results
      combined_prompt = "#{original_prompt}\n\nTool execution results:\n#{tool_outputs.join("\n\n")}\n\nBased on these tool results, please provide your response."

      # Make another responses API call with the tool results
      execute_responses_api(combined_prompt, {})
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
        "(#{response["total_cost"]} - #{response["duration_ms"]}ms) #{instance_info} -> #{caller_info}: \n---\n#{response["result"]}\n---"
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

    class ExecutionError < StandardError; end
  end
end
