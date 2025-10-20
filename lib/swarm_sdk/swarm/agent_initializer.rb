# frozen_string_literal: true

module SwarmSDK
  class Swarm
    # Handles the complex 5-pass agent initialization process
    #
    # Responsibilities:
    # - Create all agent chat instances (pass 1)
    # - Register delegation tools (pass 2)
    # - Setup agent contexts (pass 3)
    # - Configure hook system (pass 4)
    # - Apply YAML hooks if present (pass 5)
    #
    # This encapsulates the complex initialization logic that was previously
    # embedded in Swarm#initialize_agents.
    class AgentInitializer
      # rubocop:disable Metrics/ParameterLists
      def initialize(swarm, agent_definitions, global_semaphore, hook_registry, scratchpad_storage, memory_storages, config_for_hooks: nil)
        # rubocop:enable Metrics/ParameterLists
        @swarm = swarm
        @agent_definitions = agent_definitions
        @global_semaphore = global_semaphore
        @hook_registry = hook_registry
        @scratchpad_storage = scratchpad_storage
        @memory_storages = memory_storages
        @config_for_hooks = config_for_hooks
        @agents = {}
        @agent_contexts = {}
      end

      # Initialize all agents with their chat instances and tools
      #
      # This implements a 5-pass algorithm:
      # 1. Create all Agent::Chat instances
      # 2. Register delegation tools (agents can call each other)
      # 3. Setup agent contexts for tracking
      # 4. Configure hook system
      # 5. Apply YAML hooks (if loaded from YAML)
      #
      # @return [Hash] agents hash { agent_name => Agent::Chat }
      def initialize_all
        pass_1_create_agents
        pass_2_register_delegation_tools
        pass_3_setup_contexts
        pass_4_configure_hooks
        pass_5_apply_yaml_hooks

        @agents
      end

      # Provide access to agent contexts for Swarm
      attr_reader :agent_contexts

      # Create a tool that delegates work to another agent
      #
      # This method is public for testing delegation from Swarm.
      #
      # @param name [String] Delegate agent name
      # @param description [String] Delegate agent description
      # @param delegate_chat [Agent::Chat] The delegate's chat instance
      # @param agent_name [Symbol] Name of the delegating agent
      # @param delegating_chat [Agent::Chat, nil] The chat instance of the agent doing the delegating
      # @return [Tools::Delegate] Delegation tool
      def create_delegation_tool(name:, description:, delegate_chat:, agent_name:, delegating_chat: nil)
        Tools::Delegate.new(
          delegate_name: name,
          delegate_description: description,
          delegate_chat: delegate_chat,
          agent_name: agent_name,
          swarm: @swarm,
          hook_registry: @hook_registry,
          delegating_chat: delegating_chat,
        )
      end

      private

      # Pass 1: Create all agent chat instances
      #
      # This creates the Agent::Chat instances but doesn't wire them together yet.
      # Each agent gets its own chat instance with configured tools.
      def pass_1_create_agents
        # Create memory storage for agents that have memory configured
        @agent_definitions.each do |agent_name, agent_definition|
          next unless agent_definition.memory_enabled?

          # Check if SwarmMemory gem is available
          unless defined?(SwarmMemory)
            raise SwarmSDK::ConfigurationError,
              "Memory configuration requires 'swarm_memory' gem. " \
                "Add to Gemfile: gem 'swarm_memory'"
          end

          # Get configured directory
          memory_config = agent_definition.memory
          memory_dir = if memory_config.respond_to?(:directory)
            memory_config.directory # MemoryConfig object (from DSL)
          else
            memory_config[:directory] || memory_config["directory"] # Hash (from YAML)
          end

          # Create SwarmMemory storage with real filesystem
          adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: memory_dir)
          @memory_storages[agent_name] = SwarmMemory::Core::Storage.new(adapter: adapter)
        end

        tool_configurator = ToolConfigurator.new(@swarm, @scratchpad_storage, @memory_storages)

        @agent_definitions.each do |name, agent_definition|
          chat = create_agent_chat(name, agent_definition, tool_configurator)
          @agents[name] = chat
        end
      end

      # Pass 2: Register agent delegation tools
      #
      # Now that all agents exist, we can create delegation tools
      # that allow agents to call each other.
      def pass_2_register_delegation_tools
        @agent_definitions.each do |name, agent_definition|
          register_delegation_tools(@agents[name], agent_definition.delegates_to, agent_name: name)
        end
      end

      # Pass 3: Setup agent contexts
      #
      # Create Agent::Context for each agent to track delegations and metadata.
      # This is needed regardless of whether logging is enabled.
      def pass_3_setup_contexts
        @agents.each do |agent_name, chat|
          agent_definition = @agent_definitions[agent_name]
          delegate_tool_names = agent_definition.delegates_to.map do |delegate_name|
            "DelegateTaskTo#{delegate_name.to_s.capitalize}"
          end

          # Create agent context
          context = Agent::Context.new(
            name: agent_name,
            delegation_tools: delegate_tool_names,
            metadata: {},
          )
          @agent_contexts[agent_name] = context

          # Always set agent context (needed for delegation tracking)
          chat.setup_context(context) if chat.respond_to?(:setup_context)

          # Configure logging callbacks if logging is enabled
          next unless LogStream.emitter

          chat.setup_logging if chat.respond_to?(:setup_logging)

          # Emit validation warnings for this agent
          emit_validation_warnings(agent_name, agent_definition)
        end
      end

      # Emit validation warnings as log events
      #
      # This validates the agent definition and emits any warnings as log events
      # through LogStream (so formatters can handle them).
      #
      # @param agent_name [Symbol] Agent name
      # @param agent_definition [Agent::Definition] Agent definition to validate
      # @return [void]
      def emit_validation_warnings(agent_name, agent_definition)
        warnings = agent_definition.validate

        warnings.each do |warning|
          case warning[:type]
          when :model_not_found
            LogStream.emit(
              type: "model_lookup_warning",
              agent: agent_name,
              model: warning[:model],
              error_message: warning[:error_message],
              suggestions: warning[:suggestions],
              timestamp: Time.now.utc.iso8601,
            )
          end
        end
      end

      # Pass 4: Configure hook system
      #
      # Setup the callback system for each agent, integrating with RubyLLM callbacks.
      def pass_4_configure_hooks
        @agents.each do |agent_name, chat|
          agent_definition = @agent_definitions[agent_name]

          # Configure callback system (integrates with RubyLLM callbacks)
          chat.setup_hooks(
            registry: @hook_registry,
            agent_definition: agent_definition,
            swarm: @swarm,
          ) if chat.respond_to?(:setup_hooks)
        end
      end

      # Pass 5: Apply YAML hooks
      #
      # If the swarm was loaded from YAML with agent-specific hooks,
      # apply them now via HooksAdapter.
      def pass_5_apply_yaml_hooks
        return unless @config_for_hooks

        @agents.each do |agent_name, chat|
          agent_def = @config_for_hooks.agents[agent_name]
          next unless agent_def&.hooks

          # Apply agent-specific hooks via Hooks::Adapter
          Hooks::Adapter.apply_agent_hooks(chat, agent_name, agent_def.hooks, @swarm.name)
        end
      end

      # Create Agent::Chat instance with rate limiting
      #
      # @param agent_name [Symbol] Agent name
      # @param agent_definition [Agent::Definition] Agent definition object
      # @param tool_configurator [ToolConfigurator] Tool configuration helper
      # @return [Agent::Chat] Configured agent chat instance
      def create_agent_chat(agent_name, agent_definition, tool_configurator)
        chat = Agent::Chat.new(
          definition: agent_definition.to_h,
          global_semaphore: @global_semaphore,
        )

        # Set agent name on provider for logging (if provider supports it)
        chat.provider.agent_name = agent_name if chat.provider.respond_to?(:agent_name=)

        # Register tools using ToolConfigurator
        tool_configurator.register_all_tools(
          chat: chat,
          agent_name: agent_name,
          agent_definition: agent_definition,
        )

        # Register MCP servers using McpConfigurator
        if agent_definition.mcp_servers.any?
          mcp_configurator = McpConfigurator.new(@swarm)
          mcp_configurator.register_mcp_servers(chat, agent_definition.mcp_servers, agent_name: agent_name)
        end

        chat
      end

      # Register agent delegation tools
      #
      # Creates delegation tools that allow one agent to call another.
      #
      # @param chat [Agent::Chat] The chat instance
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

          tool = create_delegation_tool(
            name: delegate_name.to_s,
            description: delegate_definition.description,
            delegate_chat: delegate_agent,
            agent_name: agent_name,
            delegating_chat: chat,
          )

          chat.with_tool(tool)
        end
      end
    end
  end
end
