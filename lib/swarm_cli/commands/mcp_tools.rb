# frozen_string_literal: true

module SwarmCLI
  module Commands
    # McpTools command starts an MCP server that exposes SwarmSDK tools.
    #
    # Usage:
    #   swarm mcp tools              # Expose all available tools
    #   swarm mcp tools Bash Grep    # Expose only Bash and Grep
    #
    # The server uses stdio transport and exposes SwarmSDK tools as MCP tools.
    class McpTools
      attr_reader :options

      def initialize(options)
        @options = options
        # Create volatile scratchpad for MCP server
        # Note: Scratchpad is always volatile - data is not persisted between sessions
        @scratchpad = SwarmSDK::Tools::Stores::ScratchpadStorage.new
      end

      def execute
        # Validate options
        options.validate!

        # Determine which tools to expose
        tools_to_expose = determine_tools

        if tools_to_expose.empty?
          $stderr.puts "Error: No tools available to expose"
          exit(1)
        end

        # Start the MCP server
        start_mcp_server(tools_to_expose)
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

      def determine_tools
        if options.tool_names.any?
          # Use specified tools
          options.tool_names.map(&:to_sym)
        else
          # Default: expose all available tools
          SwarmSDK::Tools::Registry.available_names
        end
      end

      def start_mcp_server(tool_names)
        require "fast_mcp"

        # Create the server
        server = FastMcp::Server.new(
          name: "swarm-tools-server",
          version: SwarmCLI::VERSION,
        )

        # Register each tool
        tool_names.each do |tool_name|
          tool_class = create_mcp_tool_wrapper(tool_name)
          server.register_tool(tool_class)
        end

        # Start with stdio transport (default)
        server.start
      end

      def create_special_tool_instance(tool_name)
        case tool_name
        when :Read
          SwarmSDK::Tools::Read.create_for_agent(:mcp)
        when :Write
          SwarmSDK::Tools::Write.create_for_agent(:mcp)
        when :Edit
          SwarmSDK::Tools::Edit.create_for_agent(:mcp)
        when :MultiEdit
          SwarmSDK::Tools::MultiEdit.create_for_agent(:mcp)
        when :TodoWrite
          SwarmSDK::Tools::TodoWrite.create_for_agent(:mcp)
        when :ScratchpadWrite
          SwarmSDK::Tools::ScratchpadWrite.create_for_scratchpad(@scratchpad)
        when :ScratchpadRead
          SwarmSDK::Tools::ScratchpadRead.create_for_scratchpad(@scratchpad)
        when :ScratchpadList
          SwarmSDK::Tools::ScratchpadList.create_for_scratchpad(@scratchpad)
        else
          raise "Unknown special tool: #{tool_name}"
        end
      end

      def create_mcp_tool_wrapper(tool_name)
        sdk_tool_class_or_special = SwarmSDK::Tools::Registry.get(tool_name)

        # Get the actual tool instance for special tools
        sdk_tool = if sdk_tool_class_or_special == :special
          create_special_tool_instance(tool_name)
        else
          sdk_tool_class_or_special.new
        end

        # Get tool metadata
        tool_description = sdk_tool.respond_to?(:description) ? sdk_tool.description : "SwarmSDK #{tool_name} tool"
        tool_params = sdk_tool.class.respond_to?(:parameters) ? sdk_tool.class.parameters : {}

        # Create an MCP tool wrapper
        Class.new(FastMcp::Tool) do
          tool_name tool_name.to_s
          description tool_description

          # Map RubyLLM parameters to fast-mcp arguments
          arguments do
            tool_params.each do |param_name, param_obj|
              param_type = param_obj.type == "integer" ? :integer : :string
              if param_obj.required
                required(param_name).filled(param_type).description(param_obj.description || "")
              else
                optional(param_name).filled(param_type).description(param_obj.description || "")
              end
            end
          end

          # Capture sdk_tool in closure
          define_method(:call) do |**kwargs|
            result = sdk_tool.execute(**kwargs)

            # Return string output for MCP
            if result.is_a?(Hash)
              result[:output] || result[:content] || result[:files]&.join("\n") || result.to_s
            else
              result.to_s
            end
          rescue StandardError => e
            "Error: #{e.message}"
          end
        end
      end
    end
  end
end
