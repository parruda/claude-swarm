# frozen_string_literal: true

module SwarmCLI
  # Registry for CLI command extensions
  #
  # Allows gems (like swarm_memory) to register additional CLI commands
  # that integrate seamlessly with the main swarm CLI.
  #
  # @example
  #   # In swarm_memory gem
  #   SwarmCLI::CommandRegistry.register(:memory, MyMemoryCommand)
  #
  #   # User runs:
  #   swarm memory status
  #
  #   # SwarmCLI routes to MyMemoryCommand.execute(["status"])
  class CommandRegistry
    @extensions = {}

    class << self
      # Register a command extension
      #
      # @param command_name [Symbol, String] Command name (e.g., :memory)
      # @param command_class [Class] Command class with execute(args) method
      # @return [void]
      #
      # @example
      #   CommandRegistry.register(:memory, SwarmMemory::CLI::Commands)
      def register(command_name, command_class)
        @extensions ||= {}
        @extensions[command_name.to_s] = command_class
      end

      # Get command class by name
      #
      # @param command_name [String] Command name
      # @return [Class, nil] Command class or nil if not found
      def get(command_name)
        @extensions ||= {}
        @extensions[command_name.to_s]
      end

      # Check if a command is registered
      #
      # @param command_name [String] Command name
      # @return [Boolean] True if command exists
      def registered?(command_name)
        @extensions ||= {}
        @extensions.key?(command_name.to_s)
      end

      # Get all registered command names
      #
      # @return [Array<String>] Command names
      def commands
        @extensions ||= {}
        @extensions.keys
      end
    end
  end
end
