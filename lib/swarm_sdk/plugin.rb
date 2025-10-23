# frozen_string_literal: true

module SwarmSDK
  # Base class for SwarmSDK plugins
  #
  # Plugins provide tools, storage, configuration parsing, and lifecycle hooks.
  # Plugins are self-registering - they call SwarmSDK::PluginRegistry.register
  # when the gem is loaded.
  #
  # @example Implementing a plugin
  #   class MyPlugin < SwarmSDK::Plugin
  #     def name
  #       :my_plugin
  #     end
  #
  #     def tools
  #       [:MyTool, :OtherTool]
  #     end
  #
  #     def create_tool(tool_name, context)
  #       # Create and return tool instance
  #     end
  #   end
  #
  #   SwarmSDK::PluginRegistry.register(MyPlugin.new)
  class Plugin
    # Plugin name (must be unique)
    #
    # @return [Symbol] Plugin identifier
    def name
      raise NotImplementedError, "#{self.class} must implement #name"
    end

    # List of tools provided by this plugin
    #
    # @return [Array<Symbol>] Tool names (e.g., [:MemoryWrite, :MemoryRead])
    def tools
      []
    end

    # Create a tool instance
    #
    # @param tool_name [Symbol] Tool name (e.g., :MemoryWrite)
    # @param context [Hash] Creation context
    #   - :agent_name [Symbol] Agent identifier
    #   - :storage [Object] Plugin storage instance (if created)
    #   - :agent_definition [Agent::Definition] Full agent definition
    #   - :chat [Agent::Chat] Chat instance (for tools that need it)
    #   - :tool_configurator [Swarm::ToolConfigurator] For tools that register other tools
    # @return [RubyLLM::Tool] Tool instance
    def create_tool(tool_name, context)
      raise NotImplementedError, "#{self.class} must implement #create_tool"
    end

    # Create plugin storage for an agent (optional)
    #
    # Called during agent initialization. Return nil if plugin doesn't need storage.
    #
    # @param agent_name [Symbol] Agent identifier
    # @param config [Object] Plugin configuration from agent definition
    # @return [Object, nil] Storage instance or nil
    def create_storage(agent_name:, config:)
      nil
    end

    # Parse plugin configuration from agent definition
    #
    # @param raw_config [Object] Raw config (DSL object or Hash from YAML)
    # @return [Object] Parsed configuration
    def parse_config(raw_config)
      raw_config
    end

    # Contribute to agent system prompt (optional)
    #
    # @param agent_definition [Agent::Definition] Agent definition
    # @param storage [Object, nil] Plugin storage instance (if created)
    # @return [String, nil] Prompt contribution or nil
    def system_prompt_contribution(agent_definition:, storage:)
      nil
    end

    # Tools that should be marked immutable (optional)
    #
    # Immutable tools cannot be removed by other tools (e.g., LoadSkill).
    #
    # @return [Array<Symbol>] Tool names
    def immutable_tools
      []
    end

    # Agent storage enabled for this agent? (optional)
    #
    # @param agent_definition [Agent::Definition] Agent definition
    # @return [Boolean] True if storage should be created
    def storage_enabled?(agent_definition)
      false
    end

    # Lifecycle: Called when agent is initialized
    #
    # @param agent_name [Symbol] Agent identifier
    # @param agent [Agent::Chat] Chat instance
    # @param context [Hash] Initialization context
    #   - :storage [Object, nil] Plugin storage
    #   - :agent_definition [Agent::Definition] Definition
    #   - :tool_configurator [Swarm::ToolConfigurator] Configurator
    def on_agent_initialized(agent_name:, agent:, context:)
      # Override if needed
    end

    # Lifecycle: Called when swarm starts
    #
    # @param swarm [Swarm] Swarm instance
    def on_swarm_started(swarm:)
      # Override if needed
    end

    # Lifecycle: Called when swarm stops
    #
    # @param swarm [Swarm] Swarm instance
    def on_swarm_stopped(swarm:)
      # Override if needed
    end

    # Lifecycle: Called on every user message
    #
    # Plugins can return system reminders to inject based on the user's prompt.
    # This enables features like semantic skill discovery, context injection, etc.
    #
    # @param agent_name [Symbol] Agent identifier
    # @param prompt [String] The user's message
    # @param is_first_message [Boolean] True if this is the first message in the conversation
    # @return [Array<String>] System reminders to inject (empty array if none)
    #
    # @example Semantic skill discovery
    #   def on_user_message(agent_name:, prompt:, is_first_message:)
    #     skills = semantic_search(prompt, threshold: 0.65)
    #     return [] if skills.empty?
    #
    #     [build_skill_reminder(skills)]
    #   end
    def on_user_message(agent_name:, prompt:, is_first_message:)
      []
    end
  end
end
