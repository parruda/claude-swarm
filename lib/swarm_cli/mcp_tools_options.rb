# frozen_string_literal: true

module SwarmCLI
  # Options for the `swarm mcp tools` command
  class McpToolsOptions
    include TTY::Option

    usage do
      program "swarm"
      commands "mcp", "tools"
      desc "Start an MCP server exposing SwarmSDK tools"
      example "swarm mcp tools"
      example "swarm mcp tools Read Write Bash"
      example "swarm mcp tools ScratchpadWrite,ScratchpadRead"
    end

    argument :tool_names do
      desc "Optional tool names to expose (defaults to all non-special tools)"
      optional
      arity :any
    end

    option :help do
      short "-h"
      long "--help"
      desc "Print usage"
    end

    def validate!
      errors = []

      # Validate tool names if provided
      if tool_names&.any?
        invalid_tools = SwarmSDK::Tools::Registry.validate(tool_names)
        if invalid_tools.any?
          available = SwarmSDK::Tools::Registry.available_names.join(", ")
          errors << "Invalid tool names: #{invalid_tools.join(", ")}. Available: #{available}"
        end
      end

      unless errors.empty?
        raise SwarmCLI::ExecutionError, errors.join("\n")
      end
    end

    # Convenience accessor
    def tool_names
      names = params[:tool_names]
      return [] if names.nil? || names.empty?

      # TTY::Option might return a string or array
      names_array = names.is_a?(Array) ? names : [names]

      # Support comma-separated tool names in addition to space-separated
      # e.g., both "swarm mcp tools Read Write" and "swarm mcp tools Read,Write" work
      names_array.flat_map { |name| name.to_s.split(",") }.map(&:strip).reject(&:empty?)
    end
  end
end
