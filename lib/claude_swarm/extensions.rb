# frozen_string_literal: true

module ClaudeSwarm
  # Extension system for claude-swarm that allows plugins to hook into
  # various points of the swarm lifecycle without modifying core code
  module Extensions
    class << self
      def initialize_extensions
        @hooks = {}
        @registered_extensions = []
      end

      # Register an extension with metadata
      def register_extension(name, metadata = {})
        @registered_extensions ||= []
        @registered_extensions << { name: name, metadata: metadata }
      end

      # Get list of registered extensions
      def registered_extensions
        @registered_extensions || []
      end

      # Register a hook callback for a specific extension point
      # @param hook_name [Symbol] The name of the hook point
      # @param priority [Integer] Priority for hook execution (lower numbers run first)
      # @param &block [Proc] The callback to execute
      def register_hook(hook_name, priority: 50, &block)
        @hooks ||= {}
        @hooks[hook_name] ||= []
        @hooks[hook_name] << { priority: priority, block: block }
        # Sort by priority (lower numbers first)
        @hooks[hook_name].sort_by! { |h| h[:priority] }
      end

      # Run all registered hooks for a given hook point
      # @param hook_name [Symbol] The name of the hook point
      # @param args [Array] Arguments to pass to the hook callbacks
      # @return [Object] The potentially modified first argument
      def run_hooks(hook_name, *args)
        @hooks ||= {}
        return args.first unless @hooks[hook_name]

        result = args.first
        @hooks[hook_name].each do |hook|
          hook_result = hook[:block].call(result, *args[1..])
          # Allow hooks to modify the result
          result = hook_result unless hook_result.nil?
        end
        result
      end

      # Check if any hooks are registered for a given hook point
      # @param hook_name [Symbol] The name of the hook point
      # @return [Boolean] True if hooks exist for this point
      def hooks_registered?(hook_name)
        @hooks ||= {}
        !@hooks[hook_name].nil? && !@hooks[hook_name].empty?
      end

      # Clear all registered hooks (useful for testing)
      def clear_hooks!
        @hooks = {}
        @registered_extensions = []
      end

      # Load extensions from standard locations
      def load_extensions
        # Load from gem's extensions directory if it exists
        gem_extensions_dir = File.expand_path("../extensions", __dir__)
        if Dir.exist?(gem_extensions_dir)
          Dir.glob(File.join(gem_extensions_dir, "*.rb")).each do |file|
            require file
          end
        end

        # Load from user's home directory
        user_extensions_file = File.expand_path("~/.claude-swarm/extensions.rb")
        require user_extensions_file if File.exist?(user_extensions_file)

        # Load from current project directory
        project_extensions_file = File.expand_path(".claude-swarm/extensions.rb")
        require project_extensions_file if File.exist?(project_extensions_file)
      end
    end

    # Initialize on module load
    initialize_extensions
  end

  # Extension hook points documentation
  module ExtensionHooks
    # Configuration hooks
    BEFORE_PARSE_CONFIG = :before_parse_config
    AFTER_PARSE_CONFIG = :after_parse_config
    VALIDATE_CONFIG = :validate_config
    VALIDATE_INSTANCE = :validate_instance

    # Orchestrator hooks
    BEFORE_SETUP = :before_setup
    AFTER_SETUP = :after_setup
    BEFORE_LAUNCH_SWARM = :before_launch_swarm
    AFTER_MCP_GENERATION = :after_mcp_generation
    BEFORE_LAUNCH_INSTANCE = :before_launch_instance
    AFTER_LAUNCH_INSTANCE = :after_launch_instance
    BEFORE_LAUNCH_MAIN = :before_launch_main
    AFTER_SWARM_COMPLETE = :after_swarm_complete

    # MCP Generator hooks
    MODIFY_MCP_CONFIG = :modify_mcp_config
    MODIFY_MCP_SERVER = :modify_mcp_server

    # CLI hooks
    REGISTER_COMMANDS = :register_commands
    BEFORE_COMMAND = :before_command
    AFTER_COMMAND = :after_command
  end
end
