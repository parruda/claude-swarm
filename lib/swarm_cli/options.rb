# frozen_string_literal: true

module SwarmCLI
  class Options
    include TTY::Option

    usage do
      program "swarm"
      command "run"
      desc "Execute a swarm with AI agents"
      example "swarm run team.yml                              # Interactive REPL"
      example "swarm run team.yml 'Build a REST API'          # REPL with initial message"
      example "echo 'Build API' | swarm run team.yml          # REPL with piped message"
      example "swarm run team.yml -p 'Build a REST API'       # Non-interactive mode"
      example "echo 'Build API' | swarm run team.yml -p       # Non-interactive from stdin"
    end

    argument :config_file do
      desc "Path to swarm configuration file (YAML)"
      required
    end

    argument :prompt_text do
      desc "Initial message for REPL or prompt for execution (optional)"
      optional
    end

    flag :prompt do
      short "-p"
      long "--prompt"
      desc "Run in non-interactive mode (reads from argument or stdin)"
    end

    option :output_format do
      long "--output-format FORMAT"
      desc "Output format: 'human' (default) or 'json'"
      default "human"
      permit ["human", "json"]
    end

    option :help do
      short "-h"
      long "--help"
      desc "Print usage"
    end

    option :version do
      short "-v"
      long "--version"
      desc "Print version"
    end

    flag :quiet do
      short "-q"
      long "--quiet"
      desc "Suppress progress output (human format only)"
    end

    flag :truncate do
      long "--truncate"
      desc "Truncate long outputs for concise view"
    end

    flag :verbose do
      long "--verbose"
      desc "Show system reminders and additional debug information"
    end

    def validate!
      errors = []

      # Config file must exist
      if config_file && !File.exist?(config_file)
        errors << "Configuration file not found: #{config_file}"
      end

      # Interactive mode cannot be used with JSON output
      if interactive_mode? && output_format == "json"
        errors << "Interactive mode is not compatible with --output-format json"
      end

      # Non-interactive mode requires a prompt
      if non_interactive_mode? && !has_prompt_source?
        errors << "Non-interactive mode (-p) requires a prompt (provide as argument or via stdin)"
      end

      unless errors.empty?
        raise SwarmCLI::ExecutionError, errors.join("\n")
      end
    end

    def interactive_mode?
      # Interactive (REPL) mode when -p flag is NOT present
      !params[:prompt]
    end

    def non_interactive_mode?
      # Non-interactive mode when -p flag IS present
      params[:prompt] == true
    end

    def initial_message
      # For REPL mode - get initial message from argument or stdin (if piped)
      return unless interactive_mode?

      if params[:prompt_text] && !params[:prompt_text].empty?
        params[:prompt_text]
      elsif !$stdin.tty?
        $stdin.read.strip
      end
    end

    def prompt_text
      # For non-interactive mode - get prompt from argument or stdin
      raise SwarmCLI::ExecutionError, "Cannot get prompt_text in interactive mode" if interactive_mode?

      @prompt_text ||= if params[:prompt_text] && !params[:prompt_text].empty?
        params[:prompt_text]
      elsif !$stdin.tty?
        $stdin.read.strip
      else
        raise SwarmCLI::ExecutionError, "No prompt provided"
      end
    end

    def has_prompt_source?
      (params[:prompt_text] && !params[:prompt_text].empty?) || !$stdin.tty?
    end

    # Convenience accessors that delegate to params
    def config_file
      params[:config_file]
    end

    def output_format
      params[:output_format]
    end

    def quiet?
      params[:quiet]
    end

    def truncate?
      params[:truncate]
    end

    def verbose?
      params[:verbose]
    end
  end
end
