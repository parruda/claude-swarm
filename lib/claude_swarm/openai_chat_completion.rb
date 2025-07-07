# frozen_string_literal: true

module ClaudeSwarm
  class OpenAIChatCompletion
    MAX_TURNS_WITH_TOOLS = 100_000 # virtually infinite

    def initialize(openai_client:, mcp_client:, available_tools:, logger:, instance_name:, model:, temperature: 0.3, reasoning_effort: nil)
      @openai_client = openai_client
      @mcp_client = mcp_client
      @available_tools = available_tools
      @executor = logger # This is actually the executor, not a logger
      @instance_name = instance_name
      @model = model
      @temperature = temperature
      @reasoning_effort = reasoning_effort
      @conversation_messages = []
    end

    def execute(prompt, options = {})
      # Build messages array
      messages = build_messages(prompt, options)

      # Process chat with recursive tool handling
      result = process_chat_completion(messages)

      # Update conversation state
      @conversation_messages = messages

      result
    end

    def reset_session
      @conversation_messages = []
    end

    private

    def build_messages(prompt, options)
      messages = []

      # Add system prompt if provided
      system_prompt = options[:system_prompt]
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

    def process_chat_completion(messages, depth = 0)
      # Prevent infinite recursion
      if depth > MAX_TURNS_WITH_TOOLS
        @executor.error("Maximum recursion depth reached in tool execution")
        return "Error: Maximum tool call depth exceeded"
      end

      # Build parameters
      parameters = {
        model: @model,
        messages: messages,
        temperature: @temperature,
      }

      # Add reasoning_effort if specified (for o-series models: o1, o1 Preview, o1-mini, o1-pro, o3, o3-mini, o3-pro, o3-deep-research, o4-mini, o4-mini-deep-research, etc.)
      parameters[:reasoning_effort] = @reasoning_effort if @reasoning_effort

      # Add tools if available
      parameters[:tools] = @mcp_client.to_openai_tools if @available_tools&.any? && @mcp_client

      # Log the request parameters
      @executor.info("Chat API Request (depth=#{depth}): #{JSON.pretty_generate(parameters)}")

      # Append to session JSON
      append_to_session_json({
        type: "openai_request",
        api: "chat",
        depth: depth,
        parameters: parameters,
      })

      # Make the API call without streaming
      begin
        response = @openai_client.chat(parameters: parameters)
      rescue StandardError => e
        @executor.error("Chat API error: #{e.class} - #{e.message}")
        @executor.error("Request parameters: #{JSON.pretty_generate(parameters)}")

        # Try to extract and log the response body for better debugging
        if e.respond_to?(:response)
          begin
            error_body = e.response[:body]
            @executor.error("Error response body: #{error_body}")
          rescue StandardError => parse_error
            @executor.error("Could not parse error response: #{parse_error.message}")
          end
        end

        # Log error to session JSON
        append_to_session_json({
          type: "openai_error",
          api: "chat",
          depth: depth,
          error: {
            class: e.class.to_s,
            message: e.message,
            response_body: e.respond_to?(:response) ? e.response[:body] : nil,
            backtrace: e.backtrace.first(5),
          },
        })

        return "Error calling OpenAI chat API: #{e.message}"
      end

      # Log the response
      @executor.info("Chat API Response (depth=#{depth}): #{JSON.pretty_generate(response)}")

      # Append to session JSON
      append_to_session_json({
        type: "openai_response",
        api: "chat",
        depth: depth,
        response: response,
      })

      # Extract the message from the response
      message = response.dig("choices", 0, "message")

      if message.nil?
        @executor.error("No message in response: #{response.inspect}")
        return "Error: No response from OpenAI"
      end

      # Check if there are tool calls
      if message["tool_calls"]
        # Add the assistant message with tool calls
        messages << {
          role: "assistant",
          content: nil,
          tool_calls: message["tool_calls"],
        }

        # Execute tools and collect results
        execute_and_append_tool_results(message["tool_calls"], messages)

        # Recursively process the next response
        process_chat_completion(messages, depth + 1)
      else
        # Regular text response - this is the final response
        response_text = message["content"] || ""
        messages << { role: "assistant", content: response_text }
        response_text
      end
    end

    def execute_and_append_tool_results(tool_calls, messages)
      # Log tool calls
      @executor.info("Executing tool calls: #{JSON.pretty_generate(tool_calls)}")

      # Append to session JSON
      append_to_session_json({
        type: "tool_calls",
        api: "chat",
        tool_calls: tool_calls,
      })

      # Execute tool calls in parallel threads
      threads = tool_calls.map do |tool_call|
        Thread.new do
          tool_name = tool_call.dig("function", "name")
          tool_args_str = tool_call.dig("function", "arguments")

          begin
            # Parse arguments
            tool_args = tool_args_str.is_a?(String) ? JSON.parse(tool_args_str) : tool_args_str

            # Log tool execution
            @executor.info("Executing tool: #{tool_name} with args: #{JSON.pretty_generate(tool_args)}")

            # Execute tool via MCP
            result = @mcp_client.call_tool(tool_name, tool_args)

            # Log result
            @executor.info("Tool result for #{tool_name}: #{result}")

            # Append to session JSON
            append_to_session_json({
              type: "tool_execution",
              tool_name: tool_name,
              arguments: tool_args,
              result: result.to_s,
            })

            # Return success result
            {
              success: true,
              tool_call_id: tool_call["id"],
              role: "tool",
              name: tool_name,
              content: result.to_s,
            }
          rescue StandardError => e
            @executor.error("Tool execution failed for #{tool_name}: #{e.message}")
            @executor.error(e.backtrace.join("\n"))

            # Append error to session JSON
            append_to_session_json({
              type: "tool_error",
              tool_name: tool_name,
              arguments: tool_args,
              error: {
                class: e.class.to_s,
                message: e.message,
                backtrace: e.backtrace.first(5),
              },
            })

            # Return error result
            {
              success: false,
              tool_call_id: tool_call["id"],
              role: "tool",
              name: tool_name,
              content: "Error: #{e.message}",
            }
          end
        end
      end

      # Collect results from all threads
      tool_results = threads.map(&:value)

      # Add all tool results to messages
      tool_results.each do |result|
        messages << {
          tool_call_id: result[:tool_call_id],
          role: result[:role],
          name: result[:name],
          content: result[:content],
        }
      end
    end

    def append_to_session_json(event)
      # Delegate to the executor's log method
      @executor.log(event) if @executor.respond_to?(:log)
    end
  end
end
