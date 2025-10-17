# frozen_string_literal: true

module SwarmCLI
  # Options for the `swarm mcp serve` command
  class McpServeOptions
    include TTY::Option

    usage do
      program "swarm"
      commands "mcp", "serve"
      desc "Start an MCP server exposing swarm lead agent as a tool"
      example "swarm mcp serve team.yml"
    end

    argument :config_file do
      desc "Path to swarm configuration file (YAML)"
      required
    end

    option :help do
      short "-h"
      long "--help"
      desc "Print usage"
    end

    def validate!
      errors = []

      # Config file must exist
      if config_file && !File.exist?(config_file)
        errors << "Configuration file not found: #{config_file}"
      end

      unless errors.empty?
        raise SwarmCLI::ExecutionError, errors.join("\n")
      end
    end

    # Convenience accessor
    def config_file
      params[:config_file]
    end
  end
end
