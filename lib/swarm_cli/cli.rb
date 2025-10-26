# frozen_string_literal: true

module SwarmCLI
  class CLI
    class << self
      def start(args)
        new(args).run
      end
    end

    def initialize(args)
      @args = args
    end

    def run
      # Handle special cases first
      if @args.empty? || @args.include?("--help") || @args.include?("-h")
        print_help
        exit(0)
      end

      if @args.include?("--version") || @args.include?("-v")
        print_version
        exit(0)
      end

      # Extract command
      command = @args.first

      # Route to command
      case command
      when "run"
        run_command(@args[1..])
      when "mcp"
        mcp_command(@args[1..])
      when "migrate"
        migrate_command(@args[1..])
      else
        # Check if it's an extension command
        if CommandRegistry.registered?(command)
          extension_command(command, @args[1..])
        else
          $stderr.puts "Unknown command: #{command}"
          $stderr.puts
          print_help
          exit(1)
        end
      end
    rescue StandardError => e
      $stderr.puts "Fatal error: #{e.message}"
      exit(1)
    end

    private

    def mcp_command(args)
      # MCP has subcommands
      subcommand = args.first

      case subcommand
      when "serve"
        mcp_serve_command(args[1..])
      when "tools"
        mcp_tools_command(args[1..])
      else
        $stderr.puts "Unknown mcp subcommand: #{subcommand}"
        $stderr.puts
        $stderr.puts "Available mcp subcommands:"
        $stderr.puts "  serve     Start an MCP server exposing swarm lead agent"
        $stderr.puts "  tools     Start an MCP server exposing SwarmSDK tools"
        exit(1)
      end
    end

    def mcp_serve_command(args)
      # Parse options
      options = McpServeOptions.new
      options.parse(args)

      # Execute mcp serve command
      Commands::McpServe.new(options).execute
    rescue TTY::Option::InvalidParameter, TTY::Option::InvalidArgument => e
      $stderr.puts "Error: #{e.message}"
      $stderr.puts
      $stderr.puts options.help
      exit(1)
    end

    def mcp_tools_command(args)
      # Parse options
      options = McpToolsOptions.new
      options.parse(args)

      # Execute mcp tools command
      Commands::McpTools.new(options).execute
    rescue TTY::Option::InvalidParameter, TTY::Option::InvalidArgument => e
      $stderr.puts "Error: #{e.message}"
      $stderr.puts
      $stderr.puts options.help
      exit(1)
    end

    def run_command(args)
      # Parse options
      options = Options.new
      options.parse(args)

      # Execute run command
      Commands::Run.new(options).execute
    rescue TTY::Option::InvalidParameter, TTY::Option::InvalidArgument => e
      $stderr.puts "Error: #{e.message}"
      $stderr.puts
      $stderr.puts options.help
      exit(1)
    end

    def migrate_command(args)
      # Parse options
      options = MigrateOptions.new
      options.parse(args)

      # Execute migrate command
      Commands::Migrate.new(options).execute
    rescue TTY::Option::InvalidParameter, TTY::Option::InvalidArgument => e
      $stderr.puts "Error: #{e.message}"
      $stderr.puts
      $stderr.puts options.help
      exit(1)
    end

    def extension_command(command_name, args)
      # Get extension command class from registry
      command_class = CommandRegistry.get(command_name)

      # Execute extension command
      command_class.execute(args)
    end

    def print_help
      puts
      puts "SwarmCLI v#{VERSION} - AI Agent Orchestration"
      puts
      puts "Usage:"
      puts "  swarm run CONFIG_FILE -p PROMPT [options]"
      puts "  swarm migrate INPUT_FILE [--output OUTPUT_FILE]"
      puts "  swarm mcp serve CONFIG_FILE"
      puts "  swarm mcp tools [TOOL_NAMES...]"

      # Show extension commands dynamically
      CommandRegistry.commands.each do |cmd|
        puts "  swarm #{cmd} ..."
      end

      puts
      puts "Commands:"
      puts "  run           Execute a swarm with AI agents"
      puts "  migrate       Migrate Claude Swarm v1 config to SwarmSDK v2 format"
      puts "  mcp serve     Start an MCP server exposing swarm lead agent"
      puts "  mcp tools     Start an MCP server exposing SwarmSDK tools"

      # Show extension command descriptions (if registered)
      if CommandRegistry.registered?("memory")
        puts "  memory        Manage SwarmMemory embeddings"
      end

      puts
      puts "Options:"
      puts "  -p, --prompt PROMPT          Task prompt for the swarm"
      puts "  -o, --output FILE            Output file for migrated config (default: stdout)"
      puts "  --output-format FORMAT       Output format: 'human' or 'json' (default: human)"
      puts "  -q, --quiet                  Suppress progress output (human format only)"
      puts "  --truncate                   Truncate long outputs for concise view"
      puts "  --verbose                    Show system reminders and additional debug information"
      puts "  -h, --help                   Print help"
      puts "  -v, --version                Print version"
      puts
      puts "Examples:"
      puts "  swarm run team.yml -p 'Build a REST API'"
      puts "  echo 'Build a REST API' | swarm run team.yml"
      puts "  swarm run team.yml -p 'Refactor code' --output-format json"
      puts "  swarm migrate old-config.yml"
      puts "  swarm migrate old-config.yml --output new-config.yml"
      puts "  swarm mcp serve team.yml"
      puts "  swarm mcp tools                              # Expose all SwarmSDK tools"
      puts "  swarm mcp tools Bash Grep Read               # Space-separated tools"
      puts "  swarm mcp tools ScratchpadWrite,ScratchpadRead  # Comma-separated tools"

      # Show extension command examples dynamically
      if CommandRegistry.registered?("memory")
        puts "  swarm memory setup                           # Setup embeddings (download model)"
        puts "  swarm memory status                          # Check embedding status"
      end

      puts
    end

    def print_version
      puts "SwarmCLI v#{VERSION}"
    end
  end
end
