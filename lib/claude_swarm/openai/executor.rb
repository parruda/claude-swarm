# frozen_string_literal: true

module ClaudeSwarm
  module OpenAI
    class Executor < BaseExecutor
      def initialize(working_directory: Dir.pwd, model: nil, mcp_config: nil, vibe: false,
        instance_name: nil, instance_id: nil, calling_instance: nil, calling_instance_id: nil,
        claude_session_id: nil, additional_directories: [], debug: false,
        temperature: nil, api_version: "chat_completion", openai_token_env: "OPENAI_API_KEY",
        base_url: nil, reasoning_effort: nil)
        # Call parent initializer for common attributes
        super(
          working_directory: working_directory,
          model: model,
          mcp_config: mcp_config,
          vibe: vibe,
          instance_name: instance_name,
          instance_id: instance_id,
          calling_instance: calling_instance,
          calling_instance_id: calling_instance_id,
          claude_session_id: claude_session_id,
          additional_directories: additional_directories,
          debug: debug
        )

        # OpenAI-specific attributes
        @temperature = temperature
        @api_version = api_version
        @base_url = base_url
        @reasoning_effort = reasoning_effort

        # Conversation state for maintaining context
        @conversation_messages = []
        @previous_response_id = nil

        # Setup OpenAI client
        setup_openai_client(openai_token_env)

        # Setup MCP client for tools
        setup_mcp_client

        # Create API handler based on api_version
        @api_handler = create_api_handler
      end

      def execute(prompt, options = {})
        # Log the request
        log_request(prompt)

        # Start timing
        start_time = Time.now

        # Execute using the appropriate handler
        result = @api_handler.execute(prompt, options)

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
        logger.error { "Unexpected error for #{@instance_name}: #{e.class} - #{e.message}" }
        logger.error { "Backtrace: #{e.backtrace.join("\n")}" }
        raise
      end

      def reset_session
        super
        @api_handler&.reset_session
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

        @openai_client = ::OpenAI::Client.new(config) do |faraday|
          # Add retry middleware with custom configuration
          faraday.request(
            :retry,
            max: 3, # Maximum number of retries
            interval: 0.5, # Initial delay between retries (in seconds)
            interval_randomness: 0.5, # Randomness factor for retry intervals
            backoff_factor: 2, # Exponential backoff factor
            exceptions: [
              Faraday::TimeoutError,
              Faraday::ConnectionFailed,
              Faraday::ServerError, # Retry on 5xx errors
            ],
            retry_statuses: [429, 500, 502, 503, 504], # HTTP status codes to retry
            retry_block: lambda do |env:, options:, retry_count:, exception:, will_retry:|
              if will_retry
                @logger.warn("Request failed (attempt #{retry_count}/#{options.max}): #{exception&.message || "HTTP #{env.status}"}. Retrying in #{options.interval * (options.backoff_factor**(retry_count - 1))} seconds...")
              else
                @logger.warn("Request failed after #{retry_count} attempts: #{exception&.message || "HTTP #{env.status}"}. Giving up.")
              end
            end,
          )
        end
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

              stdio_config = MCPClient.stdio_config(
                command: command_array,
                name: name,
              )
              stdio_config[:read_timeout] = 1800
              mcp_configs << stdio_config
            when "sse"
              logger.warn { "SSE MCP servers not yet supported for OpenAI instances: #{name}" }
              # TODO: Add SSE support when available in ruby-mcp-client
            end
          end

          if mcp_configs.any?
            # Create MCP client with unbundled environment to avoid bundler conflicts
            # This ensures MCP servers run in a clean environment without inheriting
            # Claude Swarm's BUNDLE_* environment variables
            Bundler.with_unbundled_env do
              @mcp_client = MCPClient.create_client(
                mcp_server_configs: mcp_configs,
                logger: @logger,
              )

              # List available tools from all MCP servers
              begin
                @available_tools = @mcp_client.list_tools
                logger.info { "Loaded #{@available_tools.size} tools from #{mcp_configs.size} MCP server(s)" }
              rescue StandardError => e
                logger.error { "Failed to load MCP tools: #{e.message}" }
                @available_tools = []
              end
            end
          end
        end
      rescue StandardError => e
        logger.error { "Failed to setup MCP client: #{e.message}" }
        @mcp_client = nil
        @available_tools = []
      end

      def calculate_cost(_result)
        # Simplified cost calculation
        # In reality, we'd need to track token usage
        "$0.00"
      end

      def create_api_handler
        handler_params = {
          openai_client: @openai_client,
          mcp_client: @mcp_client,
          available_tools: @available_tools,
          executor: self,
          instance_name: @instance_name,
          model: @model,
          temperature: @temperature,
          reasoning_effort: @reasoning_effort,
        }

        if @api_version == "responses"
          OpenAI::Responses.new(**handler_params)
        else
          OpenAI::ChatCompletion.new(**handler_params)
        end
      end

      def log_streaming_content(content)
        # Log streaming content similar to ClaudeCodeExecutor
        logger.debug { "#{instance_info} streaming: #{content}" }
      end
    end
  end
end
