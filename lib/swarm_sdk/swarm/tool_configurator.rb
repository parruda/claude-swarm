# frozen_string_literal: true

module SwarmSDK
  class Swarm
    # Handles tool creation, registration, and permissions wrapping
    #
    # Responsibilities:
    # - Register explicit tools for agents
    # - Register default tools (Read, Grep, Glob, etc.)
    # - Create tool instances (with agent context)
    # - Wrap tools with permissions validators
    #
    # This encapsulates all tool-related logic that was previously in Swarm.
    class ToolConfigurator
      # Default tools available to all agents (unless include_default_tools: false)
      DEFAULT_TOOLS = [
        :Read,
        :Grep,
        :Glob,
        :TodoWrite,
        :ScratchpadWrite,
        :ScratchpadRead,
        :ScratchpadList,
        :Think,
      ].freeze

      def initialize(swarm, scratchpad)
        @swarm = swarm
        @scratchpad = scratchpad
      end

      # Register all tools for an agent (both explicit and default)
      #
      # @param chat [AgentChat] The chat instance to register tools with
      # @param agent_name [Symbol] Name of the agent
      # @param agent_definition [AgentDefinition] Agent definition object
      def register_all_tools(chat:, agent_name:, agent_definition:)
        register_explicit_tools(chat, agent_definition.tools, agent_name: agent_name, agent_definition: agent_definition)
        register_default_tools(chat, agent_name: agent_name, agent_definition: agent_definition)
      end

      # Create a tool instance by name
      #
      # File tools and TodoWrite require agent context for tracking state.
      # Scratchpad tools require shared scratchpad instance.
      #
      # This method is public for testing delegation from Swarm.
      #
      # @param tool_name [Symbol, String] Tool name
      # @param agent_name [Symbol] Agent name for context
      # @param directory [String] Agent's working directory
      # @return [RubyLLM::Tool] Tool instance
      def create_tool_instance(tool_name, agent_name, directory)
        tool_name_sym = tool_name.to_sym

        case tool_name_sym
        when :Read
          Tools::Read.new(agent_name: agent_name, directory: directory)
        when :Write
          Tools::Write.new(agent_name: agent_name, directory: directory)
        when :Edit
          Tools::Edit.new(agent_name: agent_name, directory: directory)
        when :MultiEdit
          Tools::MultiEdit.new(agent_name: agent_name, directory: directory)
        when :Bash
          Tools::Bash.new(directory: directory)
        when :Glob
          Tools::Glob.new(directory: directory)
        when :Grep
          Tools::Grep.new(directory: directory)
        when :TodoWrite
          Tools::TodoWrite.new(agent_name: agent_name) # TodoWrite doesn't need directory
        when :ScratchpadWrite
          Tools::ScratchpadWrite.create_for_scratchpad(@scratchpad)
        when :ScratchpadRead
          Tools::ScratchpadRead.create_for_scratchpad(@scratchpad)
        when :ScratchpadList
          Tools::ScratchpadList.create_for_scratchpad(@scratchpad)
        when :Think
          Tools::Think.new
        else
          # Regular tools - get class from registry and instantiate
          tool_class = Tools::Registry.get(tool_name_sym)
          raise ConfigurationError, "Unknown tool: #{tool_name}" unless tool_class

          tool_class.new
        end
      end

      # Wrap a tool instance with permissions validator if configured
      #
      # This method is public for testing delegation from Swarm.
      #
      # @param tool_instance [RubyLLM::Tool] Tool instance to wrap
      # @param permissions_config [Hash, nil] Permission configuration
      # @param agent_definition [AgentDefinition] Agent definition
      # @return [RubyLLM::Tool] Either the wrapped tool or original tool
      def wrap_tool_with_permissions(tool_instance, permissions_config, agent_definition)
        # Skip wrapping if no permissions or agent bypasses permissions
        return tool_instance unless permissions_config
        return tool_instance if agent_definition.bypass_permissions

        # Create permissions config and wrap tool with validator
        permissions = Permissions::Config.new(
          permissions_config,
          base_directory: agent_definition.directory,
        )

        Permissions::Validator.new(tool_instance, permissions)
      end

      private

      # Register explicitly configured tools
      #
      # @param chat [AgentChat] The chat instance
      # @param tool_configs [Array<Hash>] Tool configurations with optional permissions
      # @param agent_name [Symbol] Agent name
      # @param agent_definition [AgentDefinition] Agent definition
      def register_explicit_tools(chat, tool_configs, agent_name:, agent_definition:)
        tool_configs.each do |tool_config|
          tool_name = tool_config[:name]
          permissions_config = tool_config[:permissions]

          # Create tool instance
          tool_instance = create_tool_instance(tool_name, agent_name, agent_definition.directory)

          # Wrap with permissions validator if configured
          tool_instance = wrap_tool_with_permissions(
            tool_instance,
            permissions_config,
            agent_definition,
          )

          chat.with_tool(tool_instance)
        end
      end

      # Register default tools for agents that have include_default_tools enabled
      #
      # @param chat [AgentChat] The chat instance
      # @param agent_name [Symbol] Agent name
      # @param agent_definition [AgentDefinition] Agent definition
      def register_default_tools(chat, agent_name:, agent_definition:)
        return unless agent_definition.include_default_tools

        # Get explicit tool names to avoid duplicates
        explicit_tool_names = agent_definition.tools.map { |t| t[:name] }.to_set

        DEFAULT_TOOLS.each do |tool_name|
          # Skip if already registered explicitly
          next if explicit_tool_names.include?(tool_name)

          # Skip Think tool if disabled via enable_think_tool flag
          next if tool_name == :Think && !agent_definition.enable_think_tool

          tool_instance = create_tool_instance(tool_name, agent_name, agent_definition.directory)

          # Resolve permissions for default tool (same logic as AgentDefinition)
          # Agent-level permissions override default permissions
          permissions_config = agent_definition.agent_permissions[tool_name] ||
            agent_definition.default_permissions[tool_name]

          # Wrap with permissions validator if configured
          tool_instance = wrap_tool_with_permissions(
            tool_instance,
            permissions_config,
            agent_definition,
          )

          chat.with_tool(tool_instance)
        end
      end

      # Register agent delegation tools
      #
      # Creates delegation tools that allow one agent to call another.
      #
      # @param chat [AgentChat] The chat instance
      # @param delegate_names [Array<Symbol>] Names of agents to delegate to
      # @param agent_name [Symbol] Name of the agent doing the delegating
      def register_delegation_tools(chat, delegate_names, agent_name:)
        return if delegate_names.empty?

        delegate_names.each do |delegate_name|
          delegate_name = delegate_name.to_sym

          unless @agents.key?(delegate_name)
            raise ConfigurationError, "Agent delegates to unknown agent '#{delegate_name}'"
          end

          # Create a tool that delegates to the specified agent
          delegate_agent = @agents[delegate_name]
          delegate_definition = @agent_definitions[delegate_name]

          tool = Tools::Delegate.new(
            delegate_name: delegate_name.to_s,
            delegate_description: delegate_definition.description,
            delegate_chat: delegate_agent,
            agent_name: agent_name,
            swarm: @swarm,
            hook_registry: @hook_registry,
            delegating_chat: chat,
          )

          chat.with_tool(tool)
        end
      end

      # Pass 4: Configure hook system
      #
      # Setup the callback system for each agent.
      def pass_4_configure_hooks
        @agents.each do |agent_name, chat|
          agent_definition = @agent_definitions[agent_name]

          chat.setup_hooks(
            registry: @hook_registry,
            agent_definition: agent_definition,
            swarm: @swarm,
          ) if chat.respond_to?(:setup_hooks)
        end
      end

      # Pass 5: Apply YAML hooks if present
      #
      # If loaded from YAML, apply agent-specific hooks.
      def pass_5_apply_yaml_hooks
        return unless @config_for_hooks

        @agents.each do |agent_name, chat|
          agent_def = @config_for_hooks.agents[agent_name]
          next unless agent_def&.hooks

          HooksAdapter.apply_agent_hooks(chat, agent_name, agent_def.hooks, @swarm.name)
        end
      end

      # Create an AgentChat instance
      #
      # NOTE: This is dead code, left over from refactoring. AgentInitializer
      # now handles agent creation. This should be removed in a cleanup pass.
      #
      # @param agent_name [Symbol] Agent name
      # @param agent_definition [AgentDefinition] Agent definition
      # @param tool_configurator [ToolConfigurator] Tool configurator
      # @return [AgentChat] Configured chat instance
      def create_agent_chat(agent_name, agent_definition, tool_configurator)
        chat = AgentChat.new(
          definition: agent_definition.to_h,
          global_semaphore: @global_semaphore,
        )

        # Set agent name on provider for logging (if provider supports it)
        chat.provider.agent_name = agent_name if chat.provider.respond_to?(:agent_name=)

        # Register tools
        tool_configurator.register_all_tools(
          chat: chat,
          agent_name: agent_name,
          agent_definition: agent_definition,
        )

        # Register MCP servers if any
        if agent_definition.mcp_servers.any?
          mcp_configurator = McpConfigurator.new(@swarm)
          mcp_configurator.register_mcp_servers(chat, agent_definition.mcp_servers, agent_name: agent_name)
        end

        chat
      end
    end
  end
end
