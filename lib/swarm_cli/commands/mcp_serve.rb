# frozen_string_literal: true

module SwarmCLI
  module Commands
    # McpServe command starts an MCP server that exposes the swarm's lead agent as a tool.
    #
    # Usage:
    #   swarm mcp serve config.yml
    #
    # The server uses stdio transport and exposes a "swarm" tool that executes tasks
    # through the configured lead agent.
    class McpServe
      attr_reader :options

      def initialize(options)
        @options = options
      end

      def execute
        # Validate options
        options.validate!

        # Load swarm configuration to validate it
        config_path = options.config_file
        unless File.exist?(config_path)
          $stderr.puts "Error: Configuration file not found: #{config_path}"
          exit(1)
        end

        # Validate the swarm configuration
        begin
          SwarmSDK.load_file(config_path)
        rescue SwarmSDK::ConfigurationError => e
          $stderr.puts "Error: Invalid swarm configuration: #{e.message}"
          exit(1)
        end

        # MCP servers should be quiet - stdout is reserved for MCP protocol
        # Errors will still be logged to stderr

        # Start the MCP server
        start_mcp_server(config_path)
      rescue Interrupt
        # User cancelled (Ctrl+C) - silent exit
        exit(130)
      rescue StandardError => e
        # Unexpected errors - always log to stderr
        $stderr.puts "Fatal error: #{e.message}"
        $stderr.puts e.backtrace.first(5).join("\n") if ENV["DEBUG"]
        exit(1)
      end

      private

      def start_mcp_server(config_path)
        require "fast_mcp"

        # Create the server
        server = FastMcp::Server.new(
          name: "swarm-mcp-server",
          version: SwarmCLI::VERSION,
        )

        # Register the swarm tool
        tool_class = create_swarm_tool_class(config_path)
        server.register_tool(tool_class)

        # Start with stdio transport (default)
        server.start
      end

      def create_swarm_tool_class(config_path)
        # Create a tool class dynamically with the config path bound
        Class.new(FastMcp::Tool) do
          # Explicit tool name required for anonymous classes
          tool_name "task"

          description "Execute tasks through the SwarmSDK lead agent"

          arguments do
            required(:task).filled(:string).description("The task or prompt to execute")
            optional(:description).filled(:string).description("Brief description of the task")
            optional(:thinking_budget).filled(:string, included_in?: ["think", "think hard", "think harder", "ultrathink"]).description("Thinking budget level")
          end

          # Store config path as class variable
          @config_path = config_path

          class << self
            attr_accessor :config_path
          end

          define_method(:call) do |task:, description: nil, thinking_budget: nil|
            # Load swarm for each execution (ensures fresh state)
            swarm = SwarmSDK.load_file(self.class.config_path)

            # Build prompt with thinking budget if provided
            prompt = task
            if thinking_budget
              prompt = "<thinking_budget>#{thinking_budget}</thinking_budget>\n\n#{task}"
            end

            # Execute the task (description is metadata only, not passed to execute)
            result = swarm.execute(prompt)

            # Check for errors
            if result.failure?
              {
                success: false,
                error: result.error.message,
                task: task,
                description: description,
              }
            else
              # On success, return just the content string
              result.content
            end
          rescue StandardError => e
            {
              success: false,
              error: e.message,
              task: task,
              description: description,
            }
          end
        end
      end
    end
  end
end
