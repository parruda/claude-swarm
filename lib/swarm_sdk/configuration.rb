# frozen_string_literal: true

module SwarmSDK
  class Configuration
    ENV_VAR_WITH_DEFAULT_PATTERN = /\$\{([^:}]+)(:=([^}]*))?\}/

    attr_reader :config_path, :swarm_name, :lead_agent, :agents

    class << self
      def load(path)
        new(path).tap(&:load_and_validate)
      end
    end

    def initialize(config_path)
      @config_path = Pathname.new(config_path).expand_path
      @config_dir = @config_path.dirname
      @agents = {}
    end

    def load_and_validate
      @config = YAML.load_file(@config_path, aliases: true)

      unless @config.is_a?(Hash)
        raise ConfigurationError, "Invalid YAML syntax: configuration must be a Hash"
      end

      @config = deep_symbolize_keys(@config)
      interpolate_env_vars!(@config)
      validate_version
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
        global_limit: Swarm::DEFAULT_GLOBAL_LIMIT,
        default_local_limit: Swarm::DEFAULT_LOCAL_LIMIT,
      )

      # Add all agents using Ruby API
      @agents.each do |name, agent_def|
        swarm.add_agent(
          name: name,
          description: agent_def.description,
          model: agent_def.model,
          system_prompt: agent_def.system_prompt,
          tools: agent_def.tools,
          delegates_to: agent_def.delegates_to,
          directories: agent_def.directories,
          temperature: agent_def.temperature,
          max_tokens: agent_def.max_tokens,
          base_url: agent_def.base_url,
          mcp_servers: agent_def.mcp_servers,
          reasoning_effort: agent_def.reasoning_effort,
        )
      end

      # Set lead agent
      swarm.lead = @lead_agent

      swarm
    end

    private

    # Recursively convert all hash keys to symbols
    def deep_symbolize_keys(obj)
      case obj
      when Hash
        obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize_keys(v) }
      when Array
        obj.map { |item| deep_symbolize_keys(item) }
      else
        obj
      end
    end

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
        agent_config ||= {}

        @agents[name] = if agent_config[:agent_file]
          load_agent_from_file(name, agent_config[:agent_file])
        else
          AgentDefinition.new(name, agent_config)
        end
      end

      unless @agents.key?(@lead_agent)
        raise ConfigurationError, "Lead agent '#{@lead_agent}' not found in agents"
      end
    end

    def load_agent_from_file(name, file_path)
      agent_file_path = resolve_agent_file_path(file_path)

      unless File.exist?(agent_file_path)
        raise ConfigurationError, "Agent file not found: #{agent_file_path}"
      end

      content = File.read(agent_file_path)
      MarkdownParser.parse(content, name)
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
