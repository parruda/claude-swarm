# frozen_string_literal: true

module SwarmSDK
  class Configuration
    ENV_VAR_WITH_DEFAULT_PATTERN = /\$\{([^:}]+)(:=([^}]*))?\}/

    attr_reader :config_path, :swarm_name, :lead_agent, :agents, :all_agents_config, :swarm_hooks, :all_agents_hooks

    class << self
      def load(path)
        new(path).tap(&:load_and_validate)
      end
    end

    def initialize(config_path)
      @config_path = Pathname.new(config_path).expand_path
      @config_dir = @config_path.dirname
      @agents = {}
      @all_agents_config = {} # Settings applied to all agents
      @swarm_hooks = {} # Swarm-level hooks (swarm_start, swarm_stop)
      @all_agents_hooks = {} # Hooks applied to all agents
    end

    def load_and_validate
      @config = YAML.load_file(@config_path, aliases: true)

      unless @config.is_a?(Hash)
        raise ConfigurationError, "Invalid YAML syntax: configuration must be a Hash"
      end

      @config = Utils.symbolize_keys(@config)
      interpolate_env_vars!(@config)
      validate_version
      load_all_agents_config
      load_hooks_config
      validate_swarm
      load_agents
      detect_circular_dependencies
      self
    rescue Errno::ENOENT
      raise ConfigurationError, "Configuration file not found: #{@config_path}"
    rescue Psych::SyntaxError => e
      raise ConfigurationError, "Invalid YAML syntax: #{e.message}"
    end

    def agent_names
      @agents.keys
    end

    def connections_for(agent_name)
      @agents[agent_name]&.delegates_to || []
    end

    # Convert configuration to Swarm instance using Ruby API
    #
    # This method bridges YAML configuration to the Ruby API, making YAML
    # a thin convenience layer over the programmatic interface.
    #
    # @return [Swarm] Configured swarm instance
    def to_swarm
      swarm = Swarm.new(
        name: @swarm_name,
        global_concurrency: Swarm::DEFAULT_GLOBAL_CONCURRENCY,
        default_local_concurrency: Swarm::DEFAULT_LOCAL_CONCURRENCY,
      )

      # Add all agents - pass definitions directly
      @agents.each do |_name, agent_def|
        swarm.add_agent(agent_def)
      end

      # Set lead agent
      swarm.lead = @lead_agent

      swarm
    end

    private

    def interpolate_env_vars!(obj)
      case obj
      when String
        interpolate_env_string(obj)
      when Hash
        obj.transform_values! { |v| interpolate_env_vars!(v) }
      when Array
        obj.map! { |v| interpolate_env_vars!(v) }
      else
        obj
      end
    end

    def interpolate_env_string(str)
      str.gsub(ENV_VAR_WITH_DEFAULT_PATTERN) do |_match|
        env_var = Regexp.last_match(1)
        has_default = Regexp.last_match(2)
        default_value = Regexp.last_match(3)

        if ENV.key?(env_var)
          ENV[env_var]
        elsif has_default
          default_value || ""
        else
          raise ConfigurationError, "Environment variable '#{env_var}' is not set"
        end
      end
    end

    def validate_version
      version = @config[:version]
      raise ConfigurationError, "Missing 'version' field in configuration" unless version
      raise ConfigurationError, "SwarmSDK requires version: 2 configuration. Got version: #{version}" unless version == 2
    end

    def load_all_agents_config
      return unless @config[:swarm]

      @all_agents_config = @config[:swarm][:all_agents] || {}
    end

    def load_hooks_config
      return unless @config[:swarm]

      # Load swarm-level hooks (only swarm_start, swarm_stop allowed)
      @swarm_hooks = Utils.symbolize_keys(@config[:swarm][:hooks] || {})

      # Load all_agents hooks (applied as swarm defaults)
      if @config[:swarm][:all_agents]
        @all_agents_hooks = Utils.symbolize_keys(@config[:swarm][:all_agents][:hooks] || {})
      end
    end

    def validate_swarm
      raise ConfigurationError, "Missing 'swarm' field in configuration" unless @config[:swarm]

      swarm = @config[:swarm]
      raise ConfigurationError, "Missing 'name' field in swarm configuration" unless swarm[:name]
      raise ConfigurationError, "Missing 'agents' field in swarm configuration" unless swarm[:agents]
      raise ConfigurationError, "Missing 'lead' field in swarm configuration" unless swarm[:lead]
      raise ConfigurationError, "No agents defined" if swarm[:agents].empty?

      @swarm_name = swarm[:name]
      @lead_agent = swarm[:lead].to_sym # Convert to symbol for consistency
    end

    def load_agents
      swarm_agents = @config[:swarm][:agents]

      swarm_agents.each do |name, agent_config|
        # Support three formats:
        # 1. String: assistant: "agents/assistant.md" (file path)
        # 2. Hash with agent_file: assistant: { agent_file: "..." }
        # 3. Hash with inline definition: assistant: { description: "...", model: "..." }

        if agent_config.is_a?(String)
          # Format 1: Direct file path as string
          file_path = agent_config
          merged_config = merge_all_agents_config({})
          @agents[name] = load_agent_from_file(name, file_path, merged_config)
        else
          # Format 2 or 3: Hash configuration
          agent_config ||= {}

          # Merge all_agents_config into agent config
          # Agent-specific config overrides all_agents config
          merged_config = merge_all_agents_config(agent_config)

          @agents[name] = if agent_config[:agent_file]
            # Format 2: Hash with agent_file key
            load_agent_from_file(name, agent_config[:agent_file], merged_config)
          else
            # Format 3: Inline definition
            Agent::Definition.new(name, merged_config)
          end
        end
      end

      unless @agents.key?(@lead_agent)
        raise ConfigurationError, "Lead agent '#{@lead_agent}' not found in agents"
      end
    end

    # Merge all_agents config with agent-specific config
    # Agent config takes precedence over all_agents config
    #
    # Merge strategy:
    # - Arrays (tools, delegates_to): Concatenate
    # - Hashes (parameters, headers): Merge (agent values override)
    # - Scalars (model, provider, base_url, timeout, coding_agent): Agent overrides
    #
    # @param agent_config [Hash] Agent-specific configuration
    # @return [Hash] Merged configuration
    def merge_all_agents_config(agent_config)
      merged = @all_agents_config.dup

      # For arrays, concatenate
      # For hashes, merge (agent values override)
      # For scalars, agent value overrides
      agent_config.each do |key, value|
        case key
        when :tools
          # Concatenate tools: all_agents.tools + agent.tools
          merged[:tools] = Array(merged[:tools]) + Array(value)
        when :delegates_to
          # Concatenate delegates_to
          merged[:delegates_to] = Array(merged[:delegates_to]) + Array(value)
        when :parameters
          # Merge parameters: all_agents.parameters + agent.parameters
          # Agent values override all_agents values for same keys
          merged[:parameters] = (merged[:parameters] || {}).merge(value || {})
        when :headers
          # Merge headers: all_agents.headers + agent.headers
          # Agent values override all_agents values for same keys
          merged[:headers] = (merged[:headers] || {}).merge(value || {})
        else
          # For everything else (model, provider, base_url, timeout, coding_agent, etc.),
          # agent value overrides all_agents value
          merged[key] = value
        end
      end

      # Pass all_agents permissions as default_permissions for backward compat with AgentDefinition
      if @all_agents_config[:permissions]
        merged[:default_permissions] = @all_agents_config[:permissions]
      end

      merged
    end

    def load_agent_from_file(name, file_path, merged_config)
      agent_file_path = resolve_agent_file_path(file_path)

      unless File.exist?(agent_file_path)
        raise ConfigurationError, "Agent file not found: #{agent_file_path}"
      end

      content = File.read(agent_file_path)
      # Parse markdown and merge with YAML config
      agent_def_from_file = MarkdownParser.parse(content, name)

      # Merge: YAML config overrides markdown file (YAML takes precedence)
      # This allows YAML to override any settings from the markdown file
      final_config = agent_def_from_file.to_h.compact.merge(merged_config.compact)

      Agent::Definition.new(name, final_config)
    rescue StandardError => e
      raise ConfigurationError, "Error loading agent '#{name}' from file '#{file_path}': #{e.message}"
    end

    def resolve_agent_file_path(file_path)
      return file_path if Pathname.new(file_path).absolute?

      @config_dir.join(file_path).to_s
    end

    def detect_circular_dependencies
      @agents.each_key do |agent_name|
        visited = Set.new
        path = []
        detect_cycle_from(agent_name, visited, path)
      end
    end

    def detect_cycle_from(agent_name, visited, path)
      return if visited.include?(agent_name)

      if path.include?(agent_name)
        cycle_start = path.index(agent_name)
        cycle = path[cycle_start..] + [agent_name]
        raise CircularDependencyError, "Circular dependency detected: #{cycle.join(" -> ")}"
      end

      path.push(agent_name)
      connections_for(agent_name).each do |connection|
        connection_sym = connection.to_sym # Convert to symbol for lookup
        unless @agents.key?(connection_sym)
          raise ConfigurationError, "Agent '#{agent_name}' has connection to unknown agent '#{connection}'"
        end

        detect_cycle_from(connection_sym, visited, path)
      end
      path.pop
      visited.add(agent_name)
    end
  end
end
