# frozen_string_literal: true

module SwarmSDK
  # Plugin registry for managing SwarmSDK extensions
  #
  # Plugins register themselves when loaded, providing tools, storage,
  # and lifecycle hooks without SwarmSDK needing to know about them.
  module PluginRegistry
    @plugins = {}
    @tool_map = {}

    class << self
      # Register a plugin
      #
      # @param plugin [Plugin] Plugin instance
      # @raise [ArgumentError] If plugin with same name already registered
      def register(plugin)
        raise ArgumentError, "Plugin must inherit from SwarmSDK::Plugin" unless plugin.is_a?(Plugin)

        name = plugin.name
        raise ArgumentError, "Plugin name required" unless name
        raise ArgumentError, "Plugin #{name} already registered" if @plugins.key?(name)

        @plugins[name] = plugin

        # Build tool → plugin mapping
        plugin.tools.each do |tool_name|
          if @tool_map.key?(tool_name)
            raise ArgumentError, "Tool #{tool_name} already registered by #{@tool_map[tool_name].name}"
          end

          @tool_map[tool_name] = plugin
        end
      end

      # Get plugin by name
      #
      # @param name [Symbol] Plugin name
      # @return [Plugin, nil] Plugin instance or nil
      def get(name)
        @plugins[name]
      end

      # Get all registered plugins
      #
      # @return [Array<Plugin>] All plugins
      def all
        @plugins.values
      end

      # Check if plugin is registered
      #
      # @param name [Symbol] Plugin name
      # @return [Boolean] True if registered
      def registered?(name)
        @plugins.key?(name)
      end

      # Get plugin that provides a tool
      #
      # @param tool_name [Symbol] Tool name
      # @return [Plugin, nil] Plugin that provides tool or nil
      def plugin_for_tool(tool_name)
        @tool_map[tool_name]
      end

      # Check if tool is provided by a plugin
      #
      # @param tool_name [Symbol] Tool name
      # @return [Boolean] True if tool is plugin-provided
      def plugin_tool?(tool_name)
        @tool_map.key?(tool_name)
      end

      # Get all tools provided by plugins
      #
      # @return [Hash<Symbol, Plugin>] Tool name → Plugin mapping
      def tools
        @tool_map.dup
      end

      # Clear all plugins (for testing)
      #
      # @return [void]
      def clear
        @plugins.clear
        @tool_map.clear
      end

      # Emit lifecycle event to all plugins
      #
      # @param event [Symbol] Event name
      # @param args [Hash] Event arguments
      def emit_event(event, **args)
        @plugins.each_value do |plugin|
          plugin.public_send(event, **args) if plugin.respond_to?(event)
        end
      end
    end
  end
end
