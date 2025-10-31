# frozen_string_literal: true

module SwarmSDK
  # Swarm orchestrates multiple AI agents with shared rate limiting and coordination.
  #
  # This is the main user-facing API for SwarmSDK. Users create swarms using:
  # - Ruby DSL: SwarmSDK.build { ... } (Recommended)
  # - YAML String: SwarmSDK.load(yaml, base_dir:)
  # - YAML File: SwarmSDK.load_file(path)
  # - Direct API: Swarm.new + add_agent (Advanced)
  #
  # ## Ruby DSL (Recommended)
  #
  #   swarm = SwarmSDK.build do
  #     name "Development Team"
  #     lead :backend
  #
  #     agent :backend do
  #       model "gpt-5"
  #       description "Backend developer"
  #       prompt "You build APIs"
  #       tools :Read, :Edit, :Bash
  #     end
  #   end
  #   result = swarm.execute("Build authentication")
  #
  # ## YAML String API
  #
  #   yaml = File.read("swarm.yml")
  #   swarm = SwarmSDK.load(yaml, base_dir: "/path/to/project")
  #   result = swarm.execute("Build authentication")
  #
  # ## YAML File API (Convenience)
  #
  #   swarm = SwarmSDK.load_file("swarm.yml")
  #   result = swarm.execute("Build authentication")
  #
  # ## Direct API (Advanced)
  #
  #   swarm = Swarm.new(name: "Development Team")
  #
  #   backend_agent = Agent::Definition.new(:backend, {
  #     description: "Backend developer",
  #     model: "gpt-5",
  #     system_prompt: "You build APIs and databases...",
  #     tools: [:Read, :Edit, :Bash],
  #     delegates_to: [:database]
  #   })
  #   swarm.add_agent(backend_agent)
  #
  #   swarm.lead = :backend
  #   result = swarm.execute("Build authentication")
  #
  # ## Architecture
  #
  # All APIs converge on Agent::Definition for validation.
  # Swarm delegates to specialized concerns:
  # - Agent::Definition: Validates configuration, builds system prompts
  # - AgentInitializer: Complex 5-pass agent setup
  # - ToolConfigurator: Tool creation and permissions (via AgentInitializer)
  # - McpConfigurator: MCP client management (via AgentInitializer)
  #
  class Swarm
    DEFAULT_GLOBAL_CONCURRENCY = 50
    DEFAULT_LOCAL_CONCURRENCY = 10
    DEFAULT_MCP_LOG_LEVEL = Logger::WARN

    # Default tools available to all agents
    DEFAULT_TOOLS = ToolConfigurator::DEFAULT_TOOLS

    attr_reader :name, :agents, :lead_agent, :mcp_clients

    # Check if scratchpad tools are enabled
    #
    # @return [Boolean]
    def scratchpad_enabled?
      @scratchpad_enabled
    end
    attr_writer :config_for_hooks

    # Class-level MCP log level configuration
    @mcp_log_level = DEFAULT_MCP_LOG_LEVEL
    @mcp_logging_configured = false

    class << self
      attr_accessor :mcp_log_level

      # Configure MCP client logging globally
      #
      # This should be called before creating any swarms that use MCP servers.
      # The configuration is global and affects all MCP clients.
      #
      # @param level [Integer] Log level (Logger::DEBUG, Logger::INFO, Logger::WARN, Logger::ERROR, Logger::FATAL)
      # @return [void]
      def configure_mcp_logging(level = DEFAULT_MCP_LOG_LEVEL)
        @mcp_log_level = level
        apply_mcp_logging_configuration
      end

      # Apply MCP logging configuration to RubyLLM::MCP
      #
      # @return [void]
      def apply_mcp_logging_configuration
        return if @mcp_logging_configured

        SwarmSDK::MCP.lazy_load

        RubyLLM::MCP.configure do |config|
          config.log_level = @mcp_log_level
        end

        @mcp_logging_configured = true
      end
    end

    # Initialize a new Swarm
    #
    # @param name [String] Human-readable swarm name
    # @param global_concurrency [Integer] Max concurrent LLM calls across entire swarm
    # @param default_local_concurrency [Integer] Default max concurrent tool calls per agent
    # @param scratchpad [Tools::Stores::Scratchpad, nil] Optional scratchpad instance (for testing)
    # @param scratchpad_enabled [Boolean] Whether to enable scratchpad tools (default: true)
    def initialize(name:, global_concurrency: DEFAULT_GLOBAL_CONCURRENCY, default_local_concurrency: DEFAULT_LOCAL_CONCURRENCY, scratchpad: nil, scratchpad_enabled: true)
      @name = name
      @global_concurrency = global_concurrency
      @default_local_concurrency = default_local_concurrency
      @scratchpad_enabled = scratchpad_enabled

      # Shared semaphore for all agents
      @global_semaphore = Async::Semaphore.new(@global_concurrency)

      # Shared scratchpad storage for all agents (volatile)
      # Use provided scratchpad storage (for testing) or create volatile one
      @scratchpad_storage = scratchpad || Tools::Stores::ScratchpadStorage.new

      # Per-agent plugin storages (persistent)
      # Format: { plugin_name => { agent_name => storage } }
      # Will be populated when agents are initialized
      @plugin_storages = {}

      # Hook registry for named hooks and swarm defaults
      @hook_registry = Hooks::Registry.new

      # Register default logging hooks
      register_default_logging_callbacks

      # Agent definitions and instances
      @agent_definitions = {}
      @agents = {}
      @agents_initialized = false
      @agent_contexts = {}

      # MCP clients per agent (for cleanup)
      @mcp_clients = Hash.new { |h, k| h[k] = [] }

      @lead_agent = nil

      # Track if first message has been sent
      @first_message_sent = false
    end

    # Add an agent to the swarm
    #
    # Accepts only Agent::Definition objects. This ensures all validation
    # happens in a single place (Agent::Definition) and keeps the API clean.
    #
    # If the definition doesn't specify max_concurrent_tools, the swarm's
    # default_local_concurrency is applied.
    #
    # @param definition [Agent::Definition] Fully configured agent definition
    # @return [self]
    #
    # @example
    #   definition = Agent::Definition.new(:backend, {
    #     description: "Backend developer",
    #     model: "gpt-5",
    #     system_prompt: "You build APIs"
    #   })
    #   swarm.add_agent(definition)
    def add_agent(definition)
      unless definition.is_a?(Agent::Definition)
        raise ArgumentError, "Expected Agent::Definition, got #{definition.class}"
      end

      name = definition.name
      raise ConfigurationError, "Agent '#{name}' already exists" if @agent_definitions.key?(name)

      # Apply swarm's default_local_concurrency if max_concurrent_tools not set
      definition.max_concurrent_tools = @default_local_concurrency if definition.max_concurrent_tools.nil?

      @agent_definitions[name] = definition
      self
    end

    # Set the lead agent (entry point for swarm execution)
    #
    # @param name [Symbol, String] Name of agent to make lead
    # @return [self]
    def lead=(name)
      name = name.to_sym

      unless @agent_definitions.key?(name)
        raise ConfigurationError, "Cannot set lead: agent '#{name}' not found"
      end

      @lead_agent = name
    end

    # Execute a task using the lead agent
    #
    # The lead agent can delegate to other agents via tool calls,
    # and the entire swarm coordinates with shared rate limiting.
    # Supports reprompting via swarm_stop hooks.
    #
    # @param prompt [String] Task to execute
    # @yield [Hash] Log entry if block given (for streaming)
    # @return [Result] Execution result
    def execute(prompt, &block)
      raise ConfigurationError, "No lead agent set. Set lead= first." unless @lead_agent

      start_time = Time.now
      logs = []
      current_prompt = prompt

      # Setup logging FIRST if block given (so swarm_start event can be emitted)
      if block_given?
        # Register callback to collect logs and forward to user's block
        LogCollector.on_log do |entry|
          logs << entry
          block.call(entry)
        end

        # Set LogStream to use LogCollector as emitter
        LogStream.emitter = LogCollector
      end

      # Trigger swarm_start hooks (before any execution)
      # Hook can append stdout to prompt (exit code 0)
      # Default callback emits swarm_start event to LogStream
      swarm_start_result = trigger_swarm_start(current_prompt)
      if swarm_start_result&.replace?
        # Hook provided stdout to append to prompt
        current_prompt = "#{current_prompt}\n\n<hook-context>\n#{swarm_start_result.value}\n</hook-context>"
      end

      # Trigger first_message hooks on first execution
      unless @first_message_sent
        trigger_first_message(current_prompt)
        @first_message_sent = true
      end

      # Lazy initialization of agents (with optional logging)
      initialize_agents unless @agents_initialized

      # Execution loop (supports reprompting)
      result = nil
      swarm_stop_triggered = false

      loop do
        # Execute within Async reactor to enable fiber scheduler for parallel execution
        # This sets Fiber.scheduler, making Faraday fiber-aware so HTTP requests yield during I/O
        # Use finished: false to suppress warnings for expected task failures
        lead = @agents[@lead_agent]
        response = Async(finished: false) do
          lead.ask(current_prompt)
        end.wait

        # Check if swarm was finished by a hook (finish_swarm)
        if response.is_a?(Hash) && response[:__finish_swarm__]
          result = Result.new(
            content: response[:message],
            agent: @lead_agent.to_s,
            logs: logs,
            duration: Time.now - start_time,
          )

          # Trigger swarm_stop hooks for event emission
          trigger_swarm_stop(result)
          swarm_stop_triggered = true

          # Break immediately - don't allow reprompting when swarm is finished by hook
          break
        end

        result = Result.new(
          content: response.content,
          agent: @lead_agent.to_s,
          logs: logs,
          duration: Time.now - start_time,
        )

        # Trigger swarm_stop hooks (for reprompt check and event emission)
        hook_result = trigger_swarm_stop(result)
        swarm_stop_triggered = true

        # Check if hook requests reprompting
        if hook_result&.reprompt?
          current_prompt = hook_result.value
          swarm_stop_triggered = false # Will trigger again in next iteration
          # Continue loop with new prompt
        else
          # Exit loop - execution complete
          break
        end
      end

      result
    rescue ConfigurationError, AgentNotFoundError
      # Re-raise configuration errors - these should be fixed, not caught
      raise
    rescue TypeError => e
      # Catch the specific "String does not have #dig method" error
      if e.message.include?("does not have #dig method")
        agent_definition = @agent_definitions[@lead_agent]
        error_msg = if agent_definition.base_url
          "LLM API request failed: The proxy/server at '#{agent_definition.base_url}' returned an invalid response. " \
            "This usually means the proxy is unreachable, requires authentication, or returned an error in non-JSON format. " \
            "Original error: #{e.message}"
        else
          "LLM API request failed with unexpected response format. Original error: #{e.message}"
        end

        result = Result.new(
          content: nil,
          agent: @lead_agent.to_s,
          error: LLMError.new(error_msg),
          logs: logs,
          duration: Time.now - start_time,
        )
      else
        result = Result.new(
          content: nil,
          agent: @lead_agent.to_s,
          error: e,
          logs: logs,
          duration: Time.now - start_time,
        )
      end
      result
    rescue StandardError => e
      result = Result.new(
        content: nil,
        agent: @lead_agent&.to_s || "unknown",
        error: e,
        logs: logs,
        duration: Time.now - start_time,
      )
      result
    ensure
      # Trigger swarm_stop if not already triggered (handles error cases)
      unless swarm_stop_triggered
        trigger_swarm_stop_final(result, start_time, logs)
      end

      # Cleanup MCP clients after execution
      cleanup

      # Reset logging state for next execution if we set it up
      #
      # IMPORTANT: Only reset if we set up logging (block_given? == true).
      # When this swarm is a mini-swarm within a NodeOrchestrator workflow,
      # the orchestrator manages LogCollector and we don't set up logging.
      #
      # Flow in NodeOrchestrator:
      # 1. NodeOrchestrator sets up LogCollector + LogStream (no block given to mini-swarms)
      # 2. Each mini-swarm executes without logging block (block_given? == false)
      # 3. Each mini-swarm skips reset (didn't set up logging)
      # 4. NodeOrchestrator resets once at the very end
      #
      # Flow in standalone swarm / interactive REPL:
      # 1. Swarm.execute sets up LogCollector + LogStream (block given)
      # 2. Swarm.execute resets in ensure block (cleanup for next call)
      if block_given?
        LogCollector.reset!
        LogStream.reset!
      end
    end

    # Get an agent chat instance by name
    #
    # @param name [Symbol, String] Agent name
    # @return [AgentChat] Agent chat instance
    def agent(name)
      name = name.to_sym
      initialize_agents unless @agents_initialized

      @agents[name] || raise(AgentNotFoundError, "Agent '#{name}' not found")
    end

    # Get an agent definition by name
    #
    # Use this to access and modify agent configuration:
    #   swarm.agent_definition(:backend).bypass_permissions = true
    #
    # @param name [Symbol, String] Agent name
    # @return [AgentDefinition] Agent definition object
    def agent_definition(name)
      name = name.to_sym

      @agent_definitions[name] || raise(AgentNotFoundError, "Agent '#{name}' not found")
    end

    # Get all agent names
    #
    # @return [Array<Symbol>] Agent names
    def agent_names
      @agent_definitions.keys
    end

    # Validate swarm configuration and return warnings
    #
    # This performs lightweight validation checks without creating agents.
    # Useful for displaying configuration warnings before execution.
    #
    # @return [Array<Hash>] Array of warning hashes from all agent definitions
    #
    # @example
    #   swarm = SwarmSDK.load_file("config.yml")
    #   warnings = swarm.validate
    #   warnings.each do |warning|
    #     puts "⚠️  #{warning[:agent]}: #{warning[:model]} not found"
    #   end
    def validate
      @agent_definitions.flat_map { |_name, definition| definition.validate }
    end

    # Emit validation warnings as log events
    #
    # This validates all agent definitions and emits any warnings as
    # model_lookup_warning events through LogStream. Useful for emitting
    # warnings before execution starts (e.g., in REPL after welcome screen).
    #
    # Requires LogStream.emitter to be set.
    #
    # @return [Array<Hash>] The validation warnings that were emitted
    #
    # @example
    #   LogCollector.on_log { |event| puts event }
    #   LogStream.emitter = LogCollector
    #   swarm.emit_validation_warnings
    def emit_validation_warnings
      warnings = validate

      warnings.each do |warning|
        case warning[:type]
        when :model_not_found
          LogStream.emit(
            type: "model_lookup_warning",
            agent: warning[:agent],
            model: warning[:model],
            error_message: warning[:error_message],
            suggestions: warning[:suggestions],
            timestamp: Time.now.utc.iso8601,
          )
        end
      end

      warnings
    end

    # Cleanup all MCP clients
    #
    # Stops all MCP client connections gracefully.
    # Should be called when the swarm is no longer needed.
    #
    # @return [void]
    def cleanup
      return if @mcp_clients.empty?

      @mcp_clients.each do |agent_name, clients|
        clients.each do |client|
          client.stop if client.alive?
          RubyLLM.logger.debug("SwarmSDK: Stopped MCP client '#{client.name}' for agent #{agent_name}")
        rescue StandardError => e
          RubyLLM.logger.error("SwarmSDK: Error stopping MCP client '#{client.name}' for agent #{agent_name}: #{e.message}")
        end
      end

      @mcp_clients.clear
    end

    # Register a named hook that can be referenced in agent configurations
    #
    # Named hooks are stored in the registry and can be referenced by symbol
    # in agent YAML configurations or programmatically.
    #
    # @param name [Symbol] Unique hook name
    # @param block [Proc] Hook implementation
    # @return [self]
    #
    # @example Register a validation hook
    #   swarm.register_hook(:validate_code) do |context|
    #     raise SwarmSDK::Hooks::Error, "Invalid" unless valid?(context.tool_call)
    #   end
    def register_hook(name, &block)
      @hook_registry.register(name, &block)
      self
    end

    # Add a swarm-level default hook that applies to all agents
    #
    # Default hooks are inherited by all agents unless overridden at agent level.
    # Useful for swarm-wide policies like logging, validation, or monitoring.
    #
    # @param event [Symbol] Event type (e.g., :pre_tool_use, :post_tool_use)
    # @param matcher [String, Regexp, nil] Optional regex pattern for tool names
    # @param priority [Integer] Execution priority (higher = earlier)
    # @param block [Proc] Hook implementation
    # @return [self]
    #
    # @example Add logging for all tool calls
    #   swarm.add_default_callback(:pre_tool_use) do |context|
    #     puts "[#{context.agent_name}] Calling #{context.tool_call.name}"
    #   end
    def add_default_callback(event, matcher: nil, priority: 0, &block)
      @hook_registry.add_default(event, matcher: matcher, priority: priority, &block)
      self
    end

    private

    # Initialize all agents using AgentInitializer
    #
    # This is called automatically (lazy initialization) by execute() and agent().
    # Delegates to AgentInitializer which handles the complex 5-pass setup.
    #
    # @return [void]
    def initialize_agents
      return if @agents_initialized

      initializer = AgentInitializer.new(
        self,
        @agent_definitions,
        @global_semaphore,
        @hook_registry,
        @scratchpad_storage,
        @plugin_storages,
        config_for_hooks: @config_for_hooks,
      )

      @agents = initializer.initialize_all
      @agent_contexts = initializer.agent_contexts
      @agents_initialized = true

      # Emit agent_start events for all agents
      emit_agent_start_events
    end

    # Emit agent_start events for all initialized agents
    def emit_agent_start_events
      # Only emit if LogStream is enabled
      return unless LogStream.emitter

      @agents.each do |agent_name, chat|
        agent_def = @agent_definitions[agent_name]

        # Build plugin storage info for logging
        plugin_storage_info = {}
        @plugin_storages.each do |plugin_name, agent_storages|
          next unless agent_storages.key?(agent_name)

          plugin_storage_info[plugin_name] = {
            enabled: true,
            # Get additional info from agent definition if available
            config: agent_def.respond_to?(plugin_name) ? extract_plugin_config_info(agent_def.public_send(plugin_name)) : nil,
          }
        end

        LogStream.emit(
          type: "agent_start",
          agent: agent_name,
          swarm_name: @name,
          model: agent_def.model,
          provider: agent_def.provider || "openai",
          directory: agent_def.directory,
          system_prompt: agent_def.system_prompt,
          tools: chat.tools.keys,
          delegates_to: agent_def.delegates_to,
          plugin_storages: plugin_storage_info,
          timestamp: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        )
      end
    end

    # Normalize tools to internal format (kept for add_agent)
    #
    # Handles both Ruby API (simple symbols) and YAML API (already parsed configs)
    #
    # @param tools [Array] Tool specifications
    # @return [Array<Hash>] Normalized tool configs
    def normalize_tools(tools)
      Array(tools).map do |tool|
        case tool
        when Symbol, String
          # Simple tool from Ruby API
          { name: tool.to_sym, permissions: nil }
        when Hash
          # Already in config format from YAML (has :name and :permissions keys)
          if tool.key?(:name)
            tool
          else
            # Inline permissions format: { Write: { allowed_paths: [...] } }
            tool_name = tool.keys.first.to_sym
            { name: tool_name, permissions: tool[tool_name] }
          end
        else
          raise ConfigurationError, "Invalid tool specification: #{tool.inspect}"
        end
      end
    end

    # Delegation methods for testing (delegate to concerns)
    # These allow tests to verify behavior without depending on internal structure

    # Create a tool instance (delegates to ToolConfigurator)
    def create_tool_instance(tool_name, agent_name, directory)
      ToolConfigurator.new(self, @scratchpad_storage, @plugin_storages).create_tool_instance(tool_name, agent_name, directory)
    end

    # Wrap tool with permissions (delegates to ToolConfigurator)
    def wrap_tool_with_permissions(tool_instance, permissions_config, agent_definition)
      ToolConfigurator.new(self, @scratchpad_storage, @plugin_storages).wrap_tool_with_permissions(tool_instance, permissions_config, agent_definition)
    end

    # Build MCP transport config (delegates to McpConfigurator)
    def build_mcp_transport_config(transport_type, config)
      McpConfigurator.new(self).build_transport_config(transport_type, config)
    end

    # Create delegation tool (delegates to AgentInitializer)
    def create_delegation_tool(name:, description:, delegate_chat:, agent_name:)
      AgentInitializer.new(self, @agent_definitions, @global_semaphore, @hook_registry, @scratchpad_storage, @plugin_storages)
        .create_delegation_tool(name: name, description: description, delegate_chat: delegate_chat, agent_name: agent_name)
    end

    # Extract loggable info from plugin config
    #
    # Attempts to extract useful information from plugin configuration
    # for logging purposes. Handles MemoryConfig, Hashes, and other objects.
    #
    # @param config [Object] Plugin configuration object
    # @return [Hash, nil] Extracted config info or nil
    def extract_plugin_config_info(config)
      return if config.nil?

      # Handle MemoryConfig object (has directory method)
      if config.respond_to?(:directory)
        return { directory: config.directory }
      end

      # Handle Hash
      if config.is_a?(Hash)
        return config.slice(:directory, "directory", :adapter, "adapter")
      end

      # Unknown config type
      nil
    end

    # Register default logging hooks that emit LogStream events
    #
    # These hooks implement the standard SwarmSDK logging behavior.
    # Users can override or extend them by registering their own hooks.
    #
    # @return [void]
    def register_default_logging_callbacks
      # Log swarm start
      add_default_callback(:swarm_start, priority: -100) do |context|
        # Only log if LogStream emitter is set (logging enabled)
        next unless LogStream.emitter

        LogStream.emit(
          type: "swarm_start",
          agent: context.metadata[:lead_agent], # Include agent for consistency
          swarm_name: context.metadata[:swarm_name],
          lead_agent: context.metadata[:lead_agent],
          prompt: context.metadata[:prompt],
          timestamp: context.metadata[:timestamp],
        )
      end

      # Log swarm stop
      add_default_callback(:swarm_stop, priority: -100) do |context|
        # Only log if LogStream emitter is set (logging enabled)
        next unless LogStream.emitter

        LogStream.emit(
          type: "swarm_stop",
          swarm_name: context.metadata[:swarm_name],
          lead_agent: context.metadata[:lead_agent],
          last_agent: context.metadata[:last_agent], # Agent that produced final response
          content: context.metadata[:content], # Final response content
          success: context.metadata[:success],
          duration: context.metadata[:duration],
          total_cost: context.metadata[:total_cost],
          total_tokens: context.metadata[:total_tokens],
          agents_involved: context.metadata[:agents_involved],
          timestamp: context.metadata[:timestamp],
        )
      end

      # Log user requests
      add_default_callback(:user_prompt, priority: -100) do |context|
        # Only log if LogStream emitter is set (logging enabled)
        next unless LogStream.emitter

        LogStream.emit(
          type: "user_prompt",
          agent: context.agent_name,
          model: context.metadata[:model] || "unknown",
          provider: context.metadata[:provider] || "unknown",
          message_count: context.metadata[:message_count] || 0,
          tools: context.metadata[:tools] || [],
          delegates_to: context.metadata[:delegates_to] || [],
          metadata: context.metadata,
        )
      end

      # Log intermediate agent responses with tool calls
      add_default_callback(:agent_step, priority: -100) do |context|
        # Only log if LogStream emitter is set (logging enabled)
        next unless LogStream.emitter

        # Extract top-level fields and remove from metadata to avoid duplication
        metadata_without_duplicates = context.metadata.except(:model, :content, :tool_calls, :finish_reason, :usage, :tool_executions)

        LogStream.emit(
          type: "agent_step",
          agent: context.agent_name,
          model: context.metadata[:model],
          content: context.metadata[:content],
          tool_calls: context.metadata[:tool_calls],
          finish_reason: context.metadata[:finish_reason],
          usage: context.metadata[:usage],
          tool_executions: context.metadata[:tool_executions],
          metadata: metadata_without_duplicates,
        )
      end

      # Log final agent responses
      add_default_callback(:agent_stop, priority: -100) do |context|
        # Only log if LogStream emitter is set (logging enabled)
        next unless LogStream.emitter

        # Extract top-level fields and remove from metadata to avoid duplication
        metadata_without_duplicates = context.metadata.except(:model, :content, :tool_calls, :finish_reason, :usage, :tool_executions)

        LogStream.emit(
          type: "agent_stop",
          agent: context.agent_name,
          model: context.metadata[:model],
          content: context.metadata[:content],
          tool_calls: context.metadata[:tool_calls],
          finish_reason: context.metadata[:finish_reason],
          usage: context.metadata[:usage],
          tool_executions: context.metadata[:tool_executions],
          metadata: metadata_without_duplicates,
        )
      end

      # Log tool calls (pre_tool_use)
      add_default_callback(:pre_tool_use, priority: -100) do |context|
        # Only log if LogStream emitter is set (logging enabled)
        next unless LogStream.emitter

        # Delegation tracking is handled separately in AgentChat
        # Just log the tool call - delegation info will be in metadata if needed
        LogStream.emit(
          type: "tool_call",
          agent: context.agent_name,
          tool_call_id: context.tool_call.id,
          tool: context.tool_call.name,
          arguments: context.tool_call.parameters,
          metadata: context.metadata,
        )
      end

      # Log tool results (post_tool_use)
      add_default_callback(:post_tool_use, priority: -100) do |context|
        # Only log if LogStream emitter is set (logging enabled)
        next unless LogStream.emitter

        # Delegation tracking is handled separately in AgentChat
        # Usage tracking is handled in agent_step/agent_stop events
        LogStream.emit(
          type: "tool_result",
          agent: context.agent_name,
          tool_call_id: context.tool_result.tool_call_id,
          tool: context.tool_result.tool_name,
          result: context.tool_result.content,
          metadata: context.metadata,
        )
      end

      # Log context warnings
      add_default_callback(:context_warning, priority: -100) do |context|
        # Only log if LogStream emitter is set (logging enabled)
        next unless LogStream.emitter

        LogStream.emit(
          type: "context_limit_warning",
          agent: context.agent_name,
          model: context.metadata[:model] || "unknown",
          threshold: "#{context.metadata[:threshold]}%",
          current_usage: "#{context.metadata[:percentage]}%",
          tokens_used: context.metadata[:tokens_used],
          tokens_remaining: context.metadata[:tokens_remaining],
          context_limit: context.metadata[:context_limit],
          metadata: context.metadata,
        )
      end
    end

    # Trigger swarm_start hooks when swarm execution begins
    #
    # This is a swarm-level event that fires when Swarm.execute is called
    # (before first user message is sent). Hooks can halt execution or append stdout to prompt.
    # Default callback emits to LogStream for logging.
    #
    # @param prompt [String] The user's task prompt
    # @return [Hooks::Result, nil] Result with stdout to append (if exit 0) or nil
    # @raise [Hooks::Error] If hook halts execution
    def trigger_swarm_start(prompt)
      context = Hooks::Context.new(
        event: :swarm_start,
        agent_name: @lead_agent.to_s,
        swarm: self,
        metadata: {
          swarm_name: @name,
          lead_agent: @lead_agent,
          prompt: prompt,
          timestamp: Time.now.utc.iso8601,
        },
      )

      executor = Hooks::Executor.new(@hook_registry, logger: RubyLLM.logger)
      result = executor.execute_safe(event: :swarm_start, context: context, callbacks: [])

      # Halt execution if hook requests it
      raise Hooks::Error, "Swarm start halted by hook: #{result.value}" if result.halt?

      # Return result so caller can check for replace (stdout injection)
      result
    rescue StandardError => e
      RubyLLM.logger.error("SwarmSDK: Error in swarm_start hook: #{e.message}")
      raise
    end

    # Trigger swarm_stop for final event emission (called in ensure block)
    #
    # This ALWAYS emits the swarm_stop event, even if there was an error.
    # It does NOT check for reprompt (that's done in trigger_swarm_stop_for_reprompt_check).
    #
    # @param result [Result, nil] Execution result (may be nil if exception before result created)
    # @param start_time [Time] Execution start time
    # @param logs [Array] Collected logs
    # @return [void]
    def trigger_swarm_stop_final(result, start_time, logs)
      # Create a minimal result if one doesn't exist (exception before result created)
      result ||= Result.new(
        content: nil,
        agent: @lead_agent&.to_s || "unknown",
        logs: logs,
        duration: Time.now - start_time,
        error: StandardError.new("Unknown error"),
      )

      context = Hooks::Context.new(
        event: :swarm_stop,
        agent_name: @lead_agent.to_s,
        swarm: self,
        metadata: {
          swarm_name: @name,
          lead_agent: @lead_agent,
          last_agent: result.agent, # Agent that produced the final response
          content: result.content, # Final response content
          success: result.success?,
          duration: result.duration,
          total_cost: result.total_cost,
          total_tokens: result.total_tokens,
          agents_involved: result.agents_involved,
          result: result,
          timestamp: Time.now.utc.iso8601,
        },
      )

      executor = Hooks::Executor.new(@hook_registry, logger: RubyLLM.logger)
      executor.execute_safe(event: :swarm_stop, context: context, callbacks: [])
    rescue StandardError => e
      # Don't let swarm_stop errors break the ensure block
      RubyLLM.logger.error("SwarmSDK: Error in swarm_stop final emission: #{e.message}")
    end

    # Trigger swarm_stop hooks for reprompt check and event emission
    #
    # This is called in the normal execution flow to check if hooks request reprompting.
    # The default callback also emits the swarm_stop event to LogStream.
    #
    # @param result [Result] The execution result
    # @return [Hooks::Result, nil] Hook result (reprompt action if applicable)
    def trigger_swarm_stop(result)
      context = Hooks::Context.new(
        event: :swarm_stop,
        agent_name: @lead_agent.to_s,
        swarm: self,
        metadata: {
          swarm_name: @name,
          lead_agent: @lead_agent,
          last_agent: result.agent, # Agent that produced the final response
          content: result.content, # Final response content
          success: result.success?,
          duration: result.duration,
          total_cost: result.total_cost,
          total_tokens: result.total_tokens,
          agents_involved: result.agents_involved,
          result: result, # Include full result for hook access
          timestamp: Time.now.utc.iso8601,
        },
      )

      executor = Hooks::Executor.new(@hook_registry, logger: RubyLLM.logger)
      hook_result = executor.execute_safe(event: :swarm_stop, context: context, callbacks: [])

      # Return hook result so caller can handle reprompt
      hook_result
    rescue StandardError => e
      RubyLLM.logger.error("SwarmSDK: Error in swarm_stop hook: #{e.message}")
      nil
    end

    # Trigger first_message hooks when first user message is sent
    #
    # This is a swarm-level event that fires once on the first call to execute().
    # Hooks can halt execution before the first message is sent.
    #
    # @param prompt [String] The first user message
    # @return [void]
    # @raise [Hooks::Error] If hook halts execution
    def trigger_first_message(prompt)
      return if @hook_registry.get_defaults(:first_message).empty?

      context = Hooks::Context.new(
        event: :first_message,
        agent_name: @lead_agent.to_s,
        swarm: self,
        metadata: {
          swarm_name: @name,
          lead_agent: @lead_agent,
          prompt: prompt,
          timestamp: Time.now.utc.iso8601,
        },
      )

      executor = Hooks::Executor.new(@hook_registry, logger: RubyLLM.logger)
      result = executor.execute_safe(event: :first_message, context: context, callbacks: [])

      # Halt execution if hook requests it
      raise Hooks::Error, "First message halted by hook: #{result.value}" if result.halt?
    rescue StandardError => e
      RubyLLM.logger.error("SwarmSDK: Error in first_message hook: #{e.message}")
      raise
    end
  end
end
