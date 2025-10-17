# frozen_string_literal: true

module SwarmCLI
  class MigrateOptions
    include TTY::Option

    usage do
      program "swarm"
      command "migrate"
      desc "Migrate a Claude Swarm v1 configuration to SwarmSDK v2 format"
      example "swarm migrate old-config.yml"
      example "swarm migrate old-config.yml --output new-config.yml"
    end

    argument :input_file do
      desc "Path to Claude Swarm v1 configuration file (YAML)"
      required
    end

    option :output do
      short "-o"
      long "--output FILE"
      desc "Output file path (if not specified, prints to stdout)"
    end

    option :help do
      short "-h"
      long "--help"
      desc "Print usage"
    end

    def validate!
      errors = []

      # Input file must exist
      if input_file && !File.exist?(input_file)
        errors << "Input file not found: #{input_file}"
      end

      unless errors.empty?
        raise SwarmCLI::ExecutionError, errors.join("\n")
      end
    end

    # Convenience accessors that delegate to params
    def input_file
      params[:input_file]
    end

    def output
      params[:output]
    end
  end
end
