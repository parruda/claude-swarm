# frozen_string_literal: true

module SwarmSDK
  class Swarm
    # Builder provides a beautiful Ruby DSL for building swarms
    #
    # The DSL combines YAML simplicity with Ruby power, enabling:
    # - Fluent, chainable configuration
    # - Hooks as Ruby blocks OR shell commands
    # - Full Ruby language features (variables, conditionals, loops)
    # - Type-safe, IDE-friendly API
    #
    # @example Basic usage
    #   swarm = SwarmSDK.build do
    #     name "Dev Team"
    #     lead :backend
    #
    #     agent :backend do
    #       model "gpt-5"
    #       prompt "You build APIs"
    #       tools :Read, :Write, :Bash
    #
    #       # Hook as Ruby block - inline logic!
    #       hook :pre_tool_use, matcher: "Bash" do |ctx|
    #         SwarmSDK::Hooks::Result.halt("Blocked!") if ctx.tool_call.parameters[:command].include?("rm -rf")
    #       end
    #     end
    #   end
    #
    #   swarm.execute("Build auth API")
    class Builder
      # Main entry point for DSL
      #
      # @example
      #   swarm = SwarmSDK.build do
      #     name "Team"
      #     agent :backend { ... }
      #   end
      class << self
        def build(&block)
          builder = new
          builder.instance_eval(&block)
          builder.build_swarm
        end
      end

      def initialize
        @swarm_name = nil
        @lead_agent = nil
        @agents = {}
        @all_agents_config = nil
        @swarm_hooks = []
        @nodes = {}
        @start_node = nil
      end

      # Set swarm name
      def name(swarm_name)
        @swarm_name = swarm_name
      end

      # Set lead agent
      def lead(agent_name)
        @lead_agent = agent_name
      end

      # Define an agent with fluent API or load from markdown content
      #
      # Supports two forms:
      # 1. Inline DSL: agent :name do ... end
      # 2. Markdown content: agent :name, <<~MD ... MD
      #
      # The name parameter is always required. If the markdown has a name field
      # in frontmatter, it will be replaced by the name parameter.
      #
      # @example Inline DSL
      #   agent :backend do
      #     model "gpt-5"
      #     system_prompt "You build APIs"
      #     tools :Read, :Write
      #
      #     hook :pre_tool_use, matcher: "Bash" do |ctx|
      #       # Inline validation logic!
      #     end
      #   end
      #
      # @example Markdown content
      #   agent :backend, <<~MD
      #     ---
      #     description: "Backend developer"
      #     model: "gpt-4"
      #     ---
      #
      #     You build APIs.
      #   MD
      def agent(name, content = nil, &block)
        # Case 1: agent :name, <<~MD do ... end (markdown + overrides)
        if content.is_a?(String) && block_given? && markdown_content?(content)
          load_agent_from_markdown_with_overrides(content, name, &block)
        # Case 2: agent :name, <<~MD (markdown only)
        elsif content.is_a?(String) && !block_given? && markdown_content?(content)
          load_agent_from_markdown(content, name)
        # Case 3: agent :name do ... end (inline DSL)
        elsif block_given?
          builder = Agent::Builder.new(name)
          builder.instance_eval(&block)
          @agents[name] = builder
        else
          raise ArgumentError, "Invalid agent definition. Use: agent :name { ... } OR agent :name, <<~MD ... MD OR agent :name, <<~MD do ... end"
        end
      end

      # Add swarm-level hook (swarm_start, swarm_stop only)
      #
      # @example Shell command
      #   hook :swarm_start, command: "echo 'Starting' >> log.txt"
      #
      # @example Ruby block
      #   hook :swarm_start do |ctx|
      #     puts "Swarm starting: #{ctx.metadata[:prompt]}"
      #   end
      def hook(event, command: nil, timeout: nil, &block)
        # Validate swarm-level events
        unless [:swarm_start, :swarm_stop].include?(event)
          raise ArgumentError, "Invalid swarm-level hook: #{event}. Only :swarm_start and :swarm_stop allowed at swarm level. Use all_agents { hook ... } or agent { hook ... } for other events."
        end

        @swarm_hooks << { event: event, command: command, timeout: timeout, block: block }
      end

      # Configure all agents with a block
      #
      # @example
      #   all_agents do
      #     tools :Read, :Write
      #
      #     hook :pre_tool_use, matcher: "Write" do |ctx|
      #       # Validation for all agents
      #     end
      #   end
      def all_agents(&block)
        builder = AllAgentsBuilder.new
        builder.instance_eval(&block)
        @all_agents_config = builder
      end

      # Define a node (mini-swarm execution stage)
      #
      # Nodes enable multi-stage workflows where different agent teams
      # collaborate in sequence. Each node is an independent swarm execution.
      #
      # @param name [Symbol] Node name
      # @yield Block for node configuration
      # @return [void]
      #
      # @example Solo agent node
      #   node :planning do
      #     agent(:architect)
      #   end
      #
      # @example Multi-agent node with delegation
      #   node :implementation do
      #     agent(:backend).delegates_to(:tester, :database)
      #     agent(:tester).delegates_to(:database)
      #     agent(:database)
      #     after :planning
      #   end
      def node(name, &block)
        builder = Node::Builder.new(name)
        builder.instance_eval(&block)
        @nodes[name] = builder
      end

      # Set the starting node for workflow execution
      #
      # Required when nodes are defined. Specifies which node to execute first.
      #
      # @param name [Symbol] Name of starting node
      # @return [void]
      #
      # @example
      #   start_node :planning
      def start_node(name)
        @start_node = name.to_sym
      end

      # Build the actual Swarm instance or NodeOrchestrator
      def build_swarm
        raise ConfigurationError, "Swarm name not set. Use: name 'My Swarm'" unless @swarm_name

        # Check if nodes are defined
        if @nodes.any?
          # Node-based workflow (agents optional for agent-less workflows)
          build_node_orchestrator
        else
          # Traditional single-swarm execution (requires agents and lead)
          raise ConfigurationError, "No agents defined. Use: agent :name { ... }" if @agents.empty?
          raise ConfigurationError, "Lead agent not set. Use: lead :agent_name" unless @lead_agent

          build_single_swarm
        end
      end

      private

      # Check if a string is markdown content (has frontmatter)
      #
      # @param str [String] String to check
      # @return [Boolean] true if string contains markdown frontmatter
      def markdown_content?(str)
        str.start_with?("---") || str.include?("\n---\n")
      end

      # Load an agent from markdown content
      #
      # Returns a hash of the agent config (not a Definition yet) so that
      # all_agents config can be applied later in the build process.
      #
      # @param content [String] Markdown content with frontmatter
      # @param name_override [Symbol, nil] Optional name to override frontmatter name
      # @return [void]
      def load_agent_from_markdown(content, name_override = nil)
        # Parse markdown content - will extract name from frontmatter if not overridden
        definition = MarkdownParser.parse(content, name_override)

        # Store the config hash (not Definition) so all_agents can be applied
        # We'll wrap this in a special marker so we know it came from markdown
        @agents[definition.name] = { __file_config__: definition.to_h }
      end

      # Load an agent from markdown content with DSL overrides
      #
      # This allows loading from a file and then overriding specific settings:
      #   agent :reviewer, File.read("reviewer.md") do
      #     provider :openai
      #     model "gpt-4o"
      #   end
      #
      # @param content [String] Markdown content with frontmatter
      # @param name_override [Symbol, nil] Optional name to override frontmatter name
      # @yield Block with DSL overrides
      # @return [void]
      def load_agent_from_markdown_with_overrides(content, name_override = nil, &block)
        # Parse markdown content first
        definition = MarkdownParser.parse(content, name_override)

        # Create a builder with the markdown config
        builder = Agent::Builder.new(definition.name)

        # Apply markdown settings to builder (these become the base)
        apply_definition_to_builder(builder, definition.to_h)

        # Apply DSL overrides (these override the markdown settings)
        builder.instance_eval(&block)

        # Store the builder (not file config) so overrides are preserved
        @agents[definition.name] = builder
      end

      # Apply agent definition hash to a builder
      #
      # @param builder [Agent::Builder] Builder to configure
      # @param config [Hash] Configuration hash from definition
      # @return [void]
      def apply_definition_to_builder(builder, config)
        builder.description(config[:description]) if config[:description]
        builder.model(config[:model]) if config[:model]
        builder.provider(config[:provider]) if config[:provider]
        builder.base_url(config[:base_url]) if config[:base_url]
        builder.api_version(config[:api_version]) if config[:api_version]
        builder.context_window(config[:context_window]) if config[:context_window]
        builder.system_prompt(config[:system_prompt]) if config[:system_prompt]
        builder.directory(config[:directory]) if config[:directory]
        builder.timeout(config[:timeout]) if config[:timeout]
        builder.parameters(config[:parameters]) if config[:parameters]
        builder.headers(config[:headers]) if config[:headers]
        builder.coding_agent(config[:coding_agent]) unless config[:coding_agent].nil?
        # Don't apply assume_model_exists from markdown - let DSL overrides or auto-enable handle it
        # builder.assume_model_exists(config[:assume_model_exists]) unless config[:assume_model_exists].nil?
        builder.bypass_permissions(config[:bypass_permissions]) if config[:bypass_permissions]
        builder.disable_default_tools(config[:disable_default_tools]) unless config[:disable_default_tools].nil?

        # Add tools from markdown
        if config[:tools]&.any?
          # Extract tool names from the tools array (which may be hashes with permissions)
          tool_names = config[:tools].map do |tool|
            tool.is_a?(Hash) ? tool[:name] : tool
          end
          builder.tools(*tool_names)
        end

        # Add delegates_to
        builder.delegates_to(*config[:delegates_to]) if config[:delegates_to]&.any?

        # Add MCP servers
        config[:mcp_servers]&.each do |server|
          builder.mcp_server(server[:name], **server.except(:name))
        end
      end

      # Build a traditional single-swarm execution
      #
      # @return [Swarm] Configured swarm instance
      def build_single_swarm
        # Create swarm using SDK
        swarm = Swarm.new(name: @swarm_name)

        # Merge all_agents config into each agent (including file-loaded ones)
        merge_all_agents_config_into_agents if @all_agents_config

        # Build definitions and add to swarm
        # Handle both Agent::Builder (inline DSL) and file configs (from files)
        @agents.each do |agent_name, agent_builder_or_config|
          definition = if agent_builder_or_config.is_a?(Hash) && agent_builder_or_config.key?(:__file_config__)
            # File-loaded agent config (with all_agents merged)
            Agent::Definition.new(agent_name, agent_builder_or_config[:__file_config__])
          else
            # Builder object (from inline DSL) - convert to definition
            agent_builder_or_config.to_definition
          end

          swarm.add_agent(definition)
        end

        # Set lead
        swarm.lead = @lead_agent

        # Apply swarm hooks (Ruby blocks)
        # These are swarm-level hooks (swarm_start, swarm_stop)
        @swarm_hooks.each do |hook_config|
          apply_swarm_hook(swarm, hook_config)
        end

        # Apply all_agents hooks (Ruby blocks)
        # These become swarm-level default callbacks that apply to all agents
        @all_agents_config&.hooks&.each do |hook_config|
          apply_all_agents_hook(swarm, hook_config)
        end

        # NOTE: Agent-specific hooks are already stored in Agent::Definition.callbacks
        # They'll be applied automatically during agent initialization (pass_4_configure_hooks)
        # This ensures they're applied at the right time, after LogStream is set up

        swarm
      end

      # Build a node-based workflow orchestrator
      #
      # @return [NodeOrchestrator] Configured orchestrator
      def build_node_orchestrator
        raise ConfigurationError, "start_node required when nodes are defined. Use: start_node :name" unless @start_node

        # Merge all_agents config into each agent (applies to all nodes)
        merge_all_agents_config_into_agents if @all_agents_config

        # Build agent definitions
        # Handle both Agent::Builder (inline DSL) and file configs (from files)
        agent_definitions = {}
        @agents.each do |agent_name, agent_builder_or_config|
          agent_definitions[agent_name] = if agent_builder_or_config.is_a?(Hash) && agent_builder_or_config.key?(:__file_config__)
            # File-loaded agent config (with all_agents merged)
            Agent::Definition.new(agent_name, agent_builder_or_config[:__file_config__])
          else
            # Builder object (from inline DSL) - convert to definition
            agent_builder_or_config.to_definition
          end
        end

        # Create node orchestrator
        NodeOrchestrator.new(
          swarm_name: @swarm_name,
          agent_definitions: agent_definitions,
          nodes: @nodes,
          start_node: @start_node,
        )
      end

      # Merge all_agents configuration into each agent
      #
      # All_agents values are used as defaults - agent-specific values override.
      # This applies to both inline DSL agents (Builder) and file-loaded agents (config hash).
      #
      # @return [void]
      def merge_all_agents_config_into_agents
        return unless @all_agents_config

        all_agents_hash = @all_agents_config.to_h

        @agents.each_value do |agent_builder_or_config|
          if agent_builder_or_config.is_a?(Hash) && agent_builder_or_config.key?(:__file_config__)
            # File-loaded agent - merge into the config hash
            file_config = agent_builder_or_config[:__file_config__]

            # Merge all_agents into file config (file config overrides)
            # Use same merge strategy as Configuration class
            merged_config = merge_all_agents_into_config(all_agents_hash, file_config)

            # Update the stored config
            agent_builder_or_config[:__file_config__] = merged_config
          else
            # Builder object (inline DSL agent)
            agent_builder = agent_builder_or_config

            # Apply all_agents defaults that haven't been set at agent level
            # Agent values override all_agents values
            apply_all_agents_defaults(agent_builder, all_agents_hash)

            # Merge tools (prepend all_agents tools)
            all_agents_tools = @all_agents_config.tools_list
            agent_builder.prepend_tools(*all_agents_tools) if all_agents_tools.any?

            # Pass all_agents permissions as default_permissions
            if @all_agents_config.permissions_config.any?
              agent_builder.default_permissions = @all_agents_config.permissions_config
            end
          end
        end
      end

      # Merge all_agents config into file-loaded agent config
      #
      # Follows same merge strategy as Configuration class:
      # - Arrays (tools, delegates_to): Concatenate (all_agents + file)
      # - Hashes (parameters, headers): Merge (file values override)
      # - Scalars (model, provider, etc.): File overrides
      #
      # @param all_agents_hash [Hash] All_agents configuration
      # @param file_config [Hash] File-loaded agent configuration
      # @return [Hash] Merged configuration
      def merge_all_agents_into_config(all_agents_hash, file_config)
        merged = all_agents_hash.dup

        file_config.each do |key, value|
          case key
          when :tools
            # Concatenate tools: all_agents.tools + file.tools
            merged[:tools] = Array(merged[:tools]) + Array(value)
          when :delegates_to
            # Concatenate delegates_to
            merged[:delegates_to] = Array(merged[:delegates_to]) + Array(value)
          when :parameters
            # Merge parameters: file values override all_agents
            merged[:parameters] = (merged[:parameters] || {}).merge(value || {})
          when :headers
            # Merge headers: file values override all_agents
            merged[:headers] = (merged[:headers] || {}).merge(value || {})
          else
            # For everything else, file value overrides all_agents value
            merged[key] = value
          end
        end

        # Pass all_agents permissions as default_permissions
        if all_agents_hash[:permissions] && !merged[:default_permissions]
          merged[:default_permissions] = all_agents_hash[:permissions]
        end

        merged
      end

      # Apply all_agents defaults to an agent builder
      #
      # Only sets values that haven't been explicitly set at the agent level.
      # This implements the override semantics: agent values take precedence.
      #
      # @param agent_builder [Agent::Builder] The agent builder to configure
      # @param all_agents_hash [Hash] All_agents configuration
      # @return [void]
      def apply_all_agents_defaults(agent_builder, all_agents_hash)
        # Model: only set if agent hasn't explicitly set it
        if all_agents_hash[:model] && !agent_builder.model_set?
          agent_builder.model(all_agents_hash[:model])
        end

        # Provider: only set if agent hasn't set it
        if all_agents_hash[:provider] && !agent_builder.provider_set?
          agent_builder.provider(all_agents_hash[:provider])
        end

        # Base URL: only set if agent hasn't set it
        if all_agents_hash[:base_url] && !agent_builder.base_url_set?
          agent_builder.base_url(all_agents_hash[:base_url])
        end

        # API Version: only set if agent hasn't set it
        if all_agents_hash[:api_version] && !agent_builder.api_version_set?
          agent_builder.api_version(all_agents_hash[:api_version])
        end

        # Timeout: only set if agent hasn't set it
        if all_agents_hash[:timeout] && !agent_builder.timeout_set?
          agent_builder.timeout(all_agents_hash[:timeout])
        end

        # Parameters: merge (all_agents + agent, agent values override)
        if all_agents_hash[:parameters]
          merged_params = all_agents_hash[:parameters].merge(agent_builder.parameters)
          agent_builder.parameters(merged_params)
        end

        # Headers: merge (all_agents + agent, agent values override)
        if all_agents_hash[:headers]
          merged_headers = all_agents_hash[:headers].merge(agent_builder.headers)
          agent_builder.headers(merged_headers)
        end

        # Coding_agent: only set if agent hasn't set it
        if !all_agents_hash[:coding_agent].nil? && !agent_builder.coding_agent_set?
          agent_builder.coding_agent(all_agents_hash[:coding_agent])
        end
      end

      def apply_swarm_hook(swarm, config)
        event = config[:event]

        if config[:block]
          # Ruby block hook - register directly
          swarm.add_default_callback(event, &config[:block])
        elsif config[:command]
          # Shell command hook - use ShellExecutor
          swarm.add_default_callback(event) do |context|
            input_json = build_hook_input(context, event)
            Hooks::ShellExecutor.execute(
              command: config[:command],
              input_json: input_json,
              timeout: config[:timeout] || 60,
              swarm_name: swarm.name,
              event: event,
            )
          end
        end
      end

      def apply_all_agents_hook(swarm, config)
        event = config[:event]
        matcher = config[:matcher]

        if config[:block]
          # Ruby block hook
          swarm.add_default_callback(event, matcher: matcher, &config[:block])
        elsif config[:command]
          # Shell command hook
          swarm.add_default_callback(event, matcher: matcher) do |context|
            input_json = build_hook_input(context, event)
            Hooks::ShellExecutor.execute(
              command: config[:command],
              input_json: input_json,
              timeout: config[:timeout] || 60,
              agent_name: context.agent_name,
              swarm_name: swarm.name,
              event: event,
            )
          end
        end
      end

      def build_hook_input(context, event)
        # Build JSON input for shell hooks (similar to HooksAdapter)
        base = { event: event.to_s }

        case event
        when :pre_tool_use
          base.merge(tool: context.tool_call.name, parameters: context.tool_call.parameters)
        when :post_tool_use
          base.merge(result: context.tool_result.content, success: context.tool_result.success?)
        when :user_prompt
          base.merge(prompt: context.metadata[:prompt])
        when :swarm_start
          base.merge(prompt: context.metadata[:prompt])
        when :swarm_stop
          base.merge(success: context.metadata[:success], duration: context.metadata[:duration])
        else
          base
        end
      end
    end
  end
end
