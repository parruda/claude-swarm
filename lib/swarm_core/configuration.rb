# frozen_string_literal: true

module SwarmCore
  class Configuration
    ENV_VAR_WITH_DEFAULT_PATTERN = /\$\{([^:}]+)(:=([^}]*))?\}/

    attr_reader :config_path, :swarm_name, :main_agent, :agents

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
      @agents[agent_name]&.connections || []
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
      version = @config["version"]
      raise ConfigurationError, "Missing 'version' field in configuration" unless version
      raise ConfigurationError, "SwarmCore requires version: 2 configuration. Got version: #{version}" unless version == 2
    end

    def validate_swarm
      raise ConfigurationError, "Missing 'swarm' field in configuration" unless @config["swarm"]

      swarm = @config["swarm"]
      raise ConfigurationError, "Missing 'name' field in swarm configuration" unless swarm["name"]
      raise ConfigurationError, "Missing 'agents' field in swarm configuration" unless swarm["agents"]
      raise ConfigurationError, "Missing 'main' field in swarm configuration" unless swarm["main"]
      raise ConfigurationError, "No agents defined" if swarm["agents"].empty?

      @swarm_name = swarm["name"]
      @main_agent = swarm["main"]
    end

    def load_agents
      swarm_agents = @config["swarm"]["agents"]

      swarm_agents.each do |name, agent_config|
        agent_config ||= {}

        @agents[name] = if agent_config["agent_file"]
          load_agent_from_file(name, agent_config["agent_file"])
        else
          AgentConfig.new(name, agent_config)
        end
      end

      unless @agents.key?(@main_agent)
        raise ConfigurationError, "Main agent '#{@main_agent}' not found in agents"
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
        unless @agents.key?(connection)
          raise ConfigurationError, "Agent '#{agent_name}' has connection to unknown agent '#{connection}'"
        end

        detect_cycle_from(connection, visited, path)
      end
      path.pop
      visited.add(agent_name)
    end
  end
end
