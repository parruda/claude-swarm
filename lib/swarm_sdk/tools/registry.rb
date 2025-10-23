# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Registry for built-in SwarmSDK tools
    #
    # Maps tool names (symbols) to their RubyLLM::Tool classes.
    # Provides validation and lookup functionality for tool registration.
    #
    # Note: Plugin-provided tools (e.g., memory tools) are NOT in this registry.
    # They are registered via SwarmSDK::PluginRegistry instead.
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
        ScratchpadWrite: :special, # Requires scratchpad storage instance
        ScratchpadRead: :special, # Requires scratchpad storage instance
        ScratchpadList: :special, # Requires scratchpad storage instance
        Think: SwarmSDK::Tools::Think,
        WebFetch: SwarmSDK::Tools::WebFetch,
        Clock: SwarmSDK::Tools::Clock,
      }.freeze

      class << self
        # Get tool class by name
        #
        # Note: Plugin-provided tools are NOT returned by this method.
        # They are managed by SwarmSDK::PluginRegistry instead.
        #
        # @param name [Symbol, String] Tool name
        # @return [Class, Symbol, nil] Tool class, :special, or nil if not found
        def get(name)
          name_sym = name.to_sym
          BUILTIN_TOOLS[name_sym]
        end

        # Get multiple tool classes by names
        #
        # @param names [Array<Symbol, String>] Tool names
        # @return [Array<Class>] Array of tool classes
        # @raise [ConfigurationError] If any tool name is invalid
        def get_many(names)
          names.map do |name|
            tool_class = get(name)
            unless tool_class
              raise ConfigurationError,
                "Unknown tool: #{name}. Available tools: #{available_names.join(", ")}"
            end

            tool_class
          end
        end

        # Check if a tool exists
        #
        # Note: Only checks built-in tools. Plugin-provided tools are checked
        # via SwarmSDK::PluginRegistry.plugin_tool?() instead.
        #
        # @param name [Symbol, String] Tool name
        # @return [Boolean]
        def exists?(name)
          name_sym = name.to_sym
          BUILTIN_TOOLS.key?(name_sym)
        end

        # Get all available built-in tool names
        #
        # Note: Does NOT include plugin-provided tools. To get all available tools
        # including plugins, combine with SwarmSDK::PluginRegistry.tools.
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
