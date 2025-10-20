# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Registry for built-in SwarmSDK tools
    #
    # Maps tool names (symbols) to their RubyLLM::Tool classes.
    # Provides validation and lookup functionality for tool registration.
    # Supports runtime extension registration for gems like swarm_memory.
    class Registry
      # All available built-in tools
      # Memory tools removed - provided by swarm_memory gem
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

      # Runtime extension registry for gems that provide tools
      @extensions = {}

      class << self
        # Register tools from an extension gem
        #
        # This allows gems like swarm_memory to register their tools at runtime.
        # Extensions are checked after built-in tools in get() and exists?().
        #
        # @param namespace [Symbol] Extension namespace (e.g., :memory)
        # @param tools [Hash] Tool name => :special or Class
        # @return [void]
        #
        # @example
        #   Registry.register_extension(:memory, {
        #     MemoryWrite: :special,
        #     MemoryRead: :special
        #   })
        def register_extension(namespace, tools)
          @extensions ||= {}
          @extensions[namespace] = tools
        end

        # Get tool class by name (checks extensions too)
        #
        # @param name [Symbol, String] Tool name
        # @return [Class, Symbol, nil] Tool class, :special, or nil if not found
        def get(name)
          name_sym = name.to_sym

          # Check built-in first
          return BUILTIN_TOOLS[name_sym] if BUILTIN_TOOLS.key?(name_sym)

          # Check extensions
          @extensions&.each_value do |tools|
            return tools[name_sym] if tools.key?(name_sym)
          end

          nil
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

        # Check if a tool exists (checks extensions too)
        #
        # @param name [Symbol, String] Tool name
        # @return [Boolean]
        def exists?(name)
          name_sym = name.to_sym
          BUILTIN_TOOLS.key?(name_sym) ||
            @extensions&.any? { |_, tools| tools.key?(name_sym) }
        end

        # Get all available tool names (includes extensions)
        #
        # @return [Array<Symbol>]
        def available_names
          names = BUILTIN_TOOLS.keys.dup
          @extensions&.each_value { |tools| names.concat(tools.keys) }
          names.uniq
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
