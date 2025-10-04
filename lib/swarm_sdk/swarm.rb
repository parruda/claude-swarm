# frozen_string_literal: true

module SwarmSDK
  # Swarm orchestrates multiple AI agents with shared rate limiting and coordination.
  #
  # This is the main user-facing API for SwarmSDK. Users create swarms either
  # programmatically via Ruby API or declaratively via YAML configuration.
  #
  # ## Ruby API (Primary)
  #
  #   swarm = Swarm.new(
  #     name: "Development Team",
  #     global_concurrency: 50,
  #     default_local_concurrency: 10
  #   )
  #
  #   swarm.add_agent(
  #     name: :backend,
  #     description: "Backend developer",
  #     model: "claude-sonnet-4",
  #     system_prompt: "You build APIs and databases...",
  #     tools: [:Read, :Edit, :Bash],
  #     delegates_to: [:database]
  #   )
  #
  #   swarm.lead = :backend
  #   result = swarm.execute("Build authentication")
  #
  # ## YAML API (Convenience)
  #
  #   swarm = Swarm.load("swarm.yml")
  #   result = swarm.execute("Build authentication")
  #
  class Swarm
    DEFAULT_GLOBAL_CONCURRENCY = 50
    DEFAULT_LOCAL_CONCURRENCY = 10

    attr_reader :name, :agents, :lead_agent

    # Initialize a new Swarm
    #
    # @param name [String] Human-readable swarm name
    # @param global_concurrency [Integer] Max concurrent LLM calls across entire swarm
    # @param default_local_concurrency [Integer] Default max concurrent tool calls per agent
    def initialize(name:, global_concurrency: DEFAULT_GLOBAL_CONCURRENCY, default_local_concurrency: DEFAULT_LOCAL_CONCURRENCY)
      @name = name
      @global_concurrency = global_concurrency
      @default_local_concurrency = default_local_concurrency

      # Shared semaphore for all agents
      @global_semaphore = Async::Semaphore.new(@global_concurrency)

      # Agent definitions and instances
      @agent_definitions = {}
      @agents = {}
      @agents_initialized = false

      @lead_agent = nil
    end

    class << self
      # Load swarm from YAML configuration file
      #
      # @param config_path [String] Path to YAML configuration file
      # @return [Swarm] Configured swarm instance
      def load(config_path)
        config = Configuration.load(config_path)
        config.to_swarm
      end
    end

    # Add an agent to the swarm
    #
    # @param name [Symbol, String] Unique agent identifier
    # @param description [String] Human-readable description
    # @param model [String] LLM model identifier
    # @param system_prompt [String] Agent's system prompt/instructions
    # @param provider [Symbol, String, nil] Provider to use (required when base_url is set)
    # @param tools [Array<Symbol>] Built-in tools available to agent
    # @param delegates_to [Array<Symbol>] Other agents this agent can delegate to
    # @param directories [Array<String>] Working directories for agent
    # @param base_url [String, nil] Custom API base URL
    # @param mcp_servers [Array<Hash>, nil] MCP server configurations
    # @param parameters [Hash, nil] LLM parameters (temperature, max_tokens, reasoning_effort, etc.)
    # @param timeout [Integer] HTTP request timeout in seconds (default: 300)
    # @param max_concurrent_tools [Integer, nil] Override default local limit
    # @return [self]
    def add_agent(
      name:,
      description:,
      model:,
      system_prompt:,
      provider: nil,
      tools: [],
      delegates_to: [],
      directories: ["."],
      base_url: nil,
      mcp_servers: [],
      parameters: nil,
      timeout: AgentDefinition::DEFAULT_TIMEOUT,
      max_concurrent_tools: nil
    )
      name = name.to_sym

      raise ConfigurationError, "Agent '#{name}' already exists" if @agent_definitions.key?(name)

      @agent_definitions[name] = {
        name: name,
        description: description,
        model: model,
        provider: provider,
        system_prompt: system_prompt,
        tools: tools,
        delegates_to: delegates_to,
        directories: directories,
        base_url: base_url,
        mcp_servers: mcp_servers,
        parameters: parameters || {},
        timeout: timeout,
        max_concurrent_tools: max_concurrent_tools || @default_local_concurrency,
      }

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
    #
    # @param prompt [String] Task to execute
    # @yield [Hash] Log entry if block given (for streaming)
    # @return [Result] Execution result
    def execute(prompt, &block)
      raise ConfigurationError, "No lead agent set. Set lead= first." unless @lead_agent

      start_time = Time.now
      logs = []

      # Setup logger if block given (streaming mode)
      if block_given?
        @logger ||= UnifiedLogger.new

        # Collect logs and forward to user's block
        @logger.on_log do |entry|
          logs << entry
          block.call(entry)
        end
      end

      # Lazy initialization of agents (with optional logging)
      initialize_agents unless @agents_initialized

      lead = @agents[@lead_agent]
      response = lead.ask(prompt)

      Result.new(
        content: response.content,
        agent: @lead_agent.to_s,
        logs: logs,
        duration: Time.now - start_time,
      )
    rescue ConfigurationError, AgentNotFoundError
      # Re-raise configuration errors - these should be fixed, not caught
      raise
    rescue TypeError => e
      # Catch the specific "String does not have #dig method" error
      if e.message.include?("does not have #dig method")
        agent_def = @agent_definitions[@lead_agent]
        error_msg = if agent_def[:base_url]
          "LLM API request failed: The proxy/server at '#{agent_def[:base_url]}' returned an invalid response. " \
            "This usually means the proxy is unreachable, requires authentication, or returned an error in non-JSON format. " \
            "Original error: #{e.message}"
        else
          "LLM API request failed with unexpected response format. Original error: #{e.message}"
        end

        Result.new(
          content: nil,
          agent: @lead_agent.to_s,
          error: LLMError.new(error_msg),
          logs: logs,
          duration: Time.now - start_time,
        )
      else
        Result.new(
          content: nil,
          agent: @lead_agent.to_s,
          error: e,
          logs: logs,
          duration: Time.now - start_time,
        )
      end
    rescue StandardError => e
      Result.new(
        content: nil,
        agent: @lead_agent&.to_s || "unknown",
        error: e,
        logs: logs,
        duration: Time.now - start_time,
      )
    end

    # Get an agent by name
    #
    # @param name [Symbol, String] Agent name
    # @return [AgentChat] Agent instance
    def agent(name)
      name = name.to_sym
      initialize_agents unless @agents_initialized

      @agents[name] || raise(AgentNotFoundError, "Agent '#{name}' not found")
    end

    # Get all agent names
    #
    # @return [Array<Symbol>] Agent names
    def agent_names
      @agent_definitions.keys
    end

    private

    # Initialize all agents with their chat instances and tools
    def initialize_agents
      # First pass: create all agent chat instances
      @agent_definitions.each do |name, definition|
        chat = create_agent_chat(definition)
        @agents[name] = chat
      end

      # Second pass: register agent tools based on delegates_to
      @agent_definitions.each do |name, definition|
        register_agent_tools(@agents[name], definition[:delegates_to])
      end

      # Third pass: attach logger to all agents if logger exists
      if @logger
        @agents.each do |agent_name, chat|
          @logger.attach_to_chat(chat, agent_name: agent_name)
        end
      end

      @agents_initialized = true
    end

    # Create AgentChat instance with rate limiting
    def create_agent_chat(definition)
      chat = AgentChat.new(
        model: definition[:model],
        provider: definition[:provider],
        global_semaphore: @global_semaphore,
        max_concurrent_tools: definition[:max_concurrent_tools],
        base_url: definition[:base_url],
        timeout: definition[:timeout],
      )

      # Configure system prompt (dedicated method)
      chat.with_instructions(definition[:system_prompt]) if definition[:system_prompt]

      # Configure all LLM parameters via with_params (including temperature)
      # RubyLLM deep merges params, so all parameters including temperature work correctly
      # Note: with_params expects keyword arguments, so we use double-splat operator
      params = definition[:parameters] || {}
      chat.with_params(**params) if params.any?

      register_builtin_tools(chat, definition[:tools])
      register_mcp_servers(chat, definition[:mcp_servers]) if definition[:mcp_servers]&.any?

      chat
    end

    # Register built-in tools for an agent
    def register_builtin_tools(chat, tool_names)
      # TODO: Implement built-in tool registration
      # For now, this is a placeholder
      # Each tool_name should map to a RubyLLM::Tool subclass
    end

    # Register MCP servers for an agent
    def register_mcp_servers(chat, mcp_server_configs)
      # TODO: Implement MCP server registration
      # For now, this is a placeholder
      # Each mcp_server_config should configure an MCP server connection
    end

    # Register agent delegation tools
    def register_agent_tools(chat, delegate_names)
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
          description: delegate_definition[:description],
          delegate_chat: delegate_agent,
        )

        chat.with_tool(tool)
      end
    end

    # Create a tool that delegates work to another agent
    def create_delegation_tool(name:, description:, delegate_chat:)
      tool_class = Class.new(RubyLLM::Tool) do
        description("Delegate tasks to #{name}. #{description}")
        param :task, desc: "Task description for the agent", required: true

        # Store delegate chat in class variable
        @delegate_chat = delegate_chat
        @tool_name = name

        class << self
          attr_reader :delegate_chat, :tool_name
        end

        # Override name to use custom name
        define_method(:name) { self.class.tool_name }

        # Execute by calling the delegate agent
        define_method(:execute) do |task:|
          response = self.class.delegate_chat.ask(task)
          halt(response.content)
        rescue Faraday::TimeoutError, Net::ReadTimeout
          halt("Error: Request to #{self.class.tool_name} timed out. The agent may be overloaded or the LLM service is not responding. Please try again or simplify the task.")
        rescue Faraday::Error => e
          halt("Error: Network error communicating with #{self.class.tool_name}: #{e.class.name}. Please check connectivity and try again.")
        rescue StandardError => e
          halt("Error: #{self.class.tool_name} encountered an error: #{e.message}")
        end
      end

      tool_class.new
    end
  end
end
