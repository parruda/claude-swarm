# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Registry for built-in SwarmSDK tools
    #
    # Maps tool names (symbols) to their RubyLLM::Tool classes.
    # Provides validation and lookup functionality for tool registration.
    class Registry
      # All available built-in tools
      BUILTIN_TOOLS = {
        Read: :special, # Requires agent context for read tracking
        Write: :special, # Requires agent context for read-before-write enforcement
        Edit: :special, # Requires agent context for read-before-edit enforcement
        Bash: SwarmSDK::Tools::Bash,
        Grep: SwarmSDK::Tools::Grep,
        Glob: SwarmSDK::Tools::Glob,
        MultiEdit: :special, # Requires agent context for read-before-edit enforcement
        TodoWrite: :special, # Requires agent context for todo tracking
        ScratchpadWrite: :special, # Requires scratchpad instance
        ScratchpadRead: :special, # Requires scratchpad instance
        ScratchpadGlob: :special, # Requires scratchpad instance
        ScratchpadGrep: :special, # Requires scratchpad instance
        Think: SwarmSDK::Tools::Think,
      }.freeze

      class << self
        # Get tool class by name
        #
        # @param name [Symbol, String] Tool name
        # @return [Class, nil] Tool class or nil if not found
        def get(name)
          BUILTIN_TOOLS[name.to_sym]
        end

        # Get multiple tool classes by names
        #
        # @param names [Array<Symbol, String>] Tool names
        # @return [Array<Class>] Array of tool classes
        # @raise [ConfigurationError] If any tool name is invalid
        def get_many(names)
          names.map do |name|
            tool_class = get(name)
            raise ConfigurationError, "Unknown tool: #{name}. Available tools: #{available_names.join(", ")}" unless tool_class

            tool_class
          end
        end

        # Check if a tool exists
        #
        # @param name [Symbol, String] Tool name
        # @return [Boolean]
        def exists?(name)
          BUILTIN_TOOLS.key?(name.to_sym)
        end

        # Get all available tool names
        #
        # @return [Array<Symbol>]
        def available_names
          BUILTIN_TOOLS.keys
        end

        # Validate tool names
        #
        # @param names [Array<Symbol, String>] Tool names to validate
        # @return [Array<Symbol>] Invalid tool names
        def validate(names)
          names.reject { |name| exists?(name) }
        end
      end
    end
  end
end
