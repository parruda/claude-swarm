# frozen_string_literal: true

module ClaudeSwarm
  class Configuration
    # Frozen constants for validation
    VALID_PROVIDERS = ["claude", "openai"].freeze
    OPENAI_SPECIFIC_FIELDS = ["temperature", "api_version", "openai_token_env", "base_url", "reasoning_effort"].freeze
    VALID_API_VERSIONS = ["chat_completion", "responses"].freeze
    VALID_REASONING_EFFORTS = ["low", "medium", "high"].freeze

    # Regex patterns
    ENV_VAR_PATTERN = /\$\{([^}]+)\}/
    ENV_VAR_WITH_DEFAULT_PATTERN = /\$\{([^:}]+)(:=([^}]*))?\}/
    O_SERIES_MODEL_PATTERN = /^o\d+(\s+(Preview|preview))?(-pro|-mini|-deep-research|-mini-deep-research)?$/

    attr_reader :config, :config_path, :swarm, :swarm_name, :main_instance, :instances

    def initialize(config_path, base_dir: nil, options: {})
      @config_path = Pathname.new(config_path).expand_path
      @config_dir = @config_path.dirname
      @base_dir = base_dir || @config_dir
      @options = options
      load_and_validate
    end

    def main_instance_config
      instances[main_instance]
    end

    def instance_names
      instances.keys
    end

    def connections_for(instance_name)
      instances[instance_name][:connections] || []
    end

    def before_commands
      @swarm["before"] || []
    end

    def after_commands
      @swarm["after"] || []
    end

    def validate_directories
      @instances.each do |name, instance|
        # Validate all directories in the directories array
        instance[:directories].each do |directory|
          raise Error, "Directory '#{directory}' for instance '#{name}' does not exist" unless File.directory?(directory)
        end
      end
    end

    private

    def has_before_commands?
      @swarm && @swarm["before"] && !@swarm["before"].empty?
    end

    def load_and_validate
      @config = YamlLoader.load_config_file(@config_path)
      interpolate_env_vars!(@config)
      validate_version
      validate_swarm
      parse_swarm
      # Skip directory validation if before commands are present
      # They might create the directories
      validate_directories unless has_before_commands?
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
          raise Error, "Environment variable '#{env_var}' is not set"
        end
      end
    end

    def validate_version
      version = @config["version"]
      raise Error, "Missing 'version' field in configuration" unless version
      raise Error, "Unsupported version: #{version}. Only version 1 is supported" unless version == 1
    end

    def validate_swarm
      raise Error, "Missing 'swarm' field in configuration" unless @config["swarm"]

      swarm = @config["swarm"]
      raise Error, "Missing 'name' field in swarm configuration" unless swarm["name"]
      raise Error, "Missing 'instances' field in swarm configuration" unless swarm["instances"]
      raise Error, "Missing 'main' field in swarm configuration" unless swarm["main"]

      raise Error, "No instances defined" if swarm["instances"].empty?

      main = swarm["main"]
      raise Error, "Main instance '#{main}' not found in instances" unless swarm["instances"].key?(main)
    end

    def parse_swarm
      @swarm = @config["swarm"]
      @swarm_name = @swarm["name"]
      @main_instance = @swarm["main"]
      @instances = {}
      @swarm["instances"].each do |name, config|
        @instances[name] = parse_instance(name, config)
      end
      validate_main_instance_provider
      validate_connections
      detect_circular_dependencies
      validate_openai_env_vars
      validate_openai_responses_api_compatibility
    end

    def parse_instance(name, config)
      config ||= {}

      # Validate required fields
      raise Error, "Instance '#{name}' missing required 'description' field" unless config["description"]

      # Parse provider (optional, defaults to claude)
      provider = config["provider"]
      model = config["model"]

      # Validate provider value if specified
      if provider && !VALID_PROVIDERS.include?(provider)
        raise Error, "Instance '#{name}' has invalid provider '#{provider}'. Must be 'claude' or 'openai'"
      end

      # Validate reasoning_effort for OpenAI provider
      if config["reasoning_effort"]
        # Ensure it's only used with OpenAI provider
        if provider != "openai"
          raise Error, "Instance '#{name}' has reasoning_effort but provider is not 'openai'"
        end

        # Validate the value
        unless VALID_REASONING_EFFORTS.include?(config["reasoning_effort"])
          raise Error, "Instance '#{name}' has invalid reasoning_effort '#{config["reasoning_effort"]}'. Must be 'low', 'medium', or 'high'"
        end

        # Validate it's only used with o-series models
        # Support patterns like: o1, o1-mini, o1-pro, o1 Preview, o3-deep-research, o4-mini-deep-research, etc.
        unless model&.match?(O_SERIES_MODEL_PATTERN)
          raise Error, "Instance '#{name}' has reasoning_effort but model '#{model}' is not an o-series model (o1, o1 Preview, o1-mini, o1-pro, o3, o3-mini, o3-pro, o3-deep-research, o4-mini, o4-mini-deep-research, etc.)"
        end
      end

      # Validate temperature is not used with o-series models when provider is openai
      if provider == "openai" && config["temperature"] && model&.match?(O_SERIES_MODEL_PATTERN)
        raise Error, "Instance '#{name}' has temperature parameter but model '#{model}' is an o-series model. O-series models use deterministic reasoning and don't accept temperature settings"
      end

      # Validate OpenAI-specific fields only when provider is not "openai"
      if provider != "openai"
        invalid_fields = OPENAI_SPECIFIC_FIELDS & config.keys
        unless invalid_fields.empty?
          raise Error, "Instance '#{name}' has OpenAI-specific fields #{invalid_fields.join(", ")} but provider is not 'openai'"
        end
      end

      # Validate api_version if specified
      if config["api_version"] && !VALID_API_VERSIONS.include?(config["api_version"])
        raise Error, "Instance '#{name}' has invalid api_version '#{config["api_version"]}'. Must be 'chat_completion' or 'responses'"
      end

      # Validate tool fields are arrays if present
      validate_tool_field(name, config, "tools")
      validate_tool_field(name, config, "allowed_tools")
      validate_tool_field(name, config, "disallowed_tools")

      # Support both 'tools' (deprecated) and 'allowed_tools' for backward compatibility
      allowed_tools = config["allowed_tools"] || config["tools"] || []

      # Parse directory field - support both string and array
      directories = parse_directories(config["directory"])

      instance_config = {
        name: name,
        directory: directories.first, # Keep single directory for backward compatibility
        directories: directories, # New field with all directories
        model: config["model"] || "sonnet",
        connections: Array(config["connections"]),
        tools: Array(allowed_tools), # Keep as 'tools' internally for compatibility
        allowed_tools: Array(allowed_tools),
        disallowed_tools: Array(config["disallowed_tools"]),
        mcps: parse_mcps(config["mcps"] || []),
        prompt: config["prompt"],
        description: config["description"],
        vibe: config["vibe"],
        worktree: parse_worktree_value(config["worktree"]),
        provider: provider, # nil means Claude (default)
        hooks: config["hooks"], # Pass hooks configuration as-is
      }

      # Add OpenAI-specific fields only when provider is "openai"
      if provider == "openai"
        instance_config[:temperature] = config["temperature"] if config["temperature"]
        instance_config[:api_version] = config["api_version"] || "chat_completion"
        instance_config[:openai_token_env] = config["openai_token_env"] || "OPENAI_API_KEY"
        instance_config[:base_url] = config["base_url"]
        instance_config[:reasoning_effort] = config["reasoning_effort"] if config["reasoning_effort"]
        # Default vibe to true for OpenAI instances if not specified
        instance_config[:vibe] = true if config["vibe"].nil?
      elsif config["vibe"].nil?
        # Default vibe to false for Claude instances if not specified
        instance_config[:vibe] = false
      end

      instance_config
    end

    def parse_mcps(mcps)
      mcps.map do |mcp|
        validate_mcp(mcp)
        mcp
      end
    end

    def validate_mcp(mcp)
      raise Error, "MCP configuration missing 'name'" unless mcp["name"]

      case mcp["type"]
      when "stdio"
        raise Error, "MCP '#{mcp["name"]}' missing 'command'" unless mcp["command"]
      when "sse", "http"
        raise Error, "MCP '#{mcp["name"]}' missing 'url'" unless mcp["url"]
      else
        raise Error, "Unknown MCP type '#{mcp["type"]}' for '#{mcp["name"]}'"
      end
    end

    def validate_connections
      @instances.each do |name, instance|
        instance[:connections].each do |connection|
          raise Error, "Instance '#{name}' has connection to unknown instance '#{connection}'" unless @instances.key?(connection)
        end
      end
    end

    def detect_circular_dependencies
      @instances.each_key do |instance_name|
        visited = Set.new
        path = []
        detect_cycle_from(instance_name, visited, path)
      end
    end

    def detect_cycle_from(instance_name, visited, path)
      return if visited.include?(instance_name)

      if path.include?(instance_name)
        cycle_start = path.index(instance_name)
        cycle = path[cycle_start..] + [instance_name]
        raise Error, "Circular dependency detected: #{cycle.join(" -> ")}"
      end

      path.push(instance_name)
      @instances[instance_name][:connections].each do |connection|
        detect_cycle_from(connection, visited, path)
      end
      path.pop
      visited.add(instance_name)
    end

    def validate_tool_field(instance_name, config, field_name)
      return unless config.key?(field_name)

      field_value = config[field_name]
      raise Error, "Instance '#{instance_name}' field '#{field_name}' must be an array, got #{field_value.class.name}" unless field_value.is_a?(Array)
    end

    def parse_directories(directory_config)
      # Default to current directory if not specified
      directory_config ||= "."

      # Convert to array and expand paths
      directories = Array(directory_config).map { |dir| expand_path(dir) }

      # Ensure at least one directory
      directories.empty? ? [expand_path(".")] : directories
    end

    def expand_path(path)
      Pathname.new(path).expand_path(@base_dir).to_s
    end

    def parse_worktree_value(value)
      return if value.nil? # Omitted means follow CLI behavior
      return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)
      return value.to_s if value.is_a?(String) && !value.empty?

      raise Error, "Invalid worktree value: #{value.inspect}. Must be true, false, or a non-empty string"
    end

    def validate_openai_env_vars
      @instances.each_value do |instance|
        next unless instance[:provider] == "openai"

        env_var = instance[:openai_token_env]
        unless ENV.key?(env_var) && !ENV[env_var].to_s.strip.empty?
          raise Error, "Environment variable '#{env_var}' is not set. OpenAI provider instances require an API key."
        end
      end
    end

    def validate_main_instance_provider
      # Only validate in interactive mode (when no prompt is provided)
      return if @options[:prompt]

      main_config = @instances[@main_instance]
      if main_config[:provider]
        raise Error, "Main instance '#{@main_instance}' cannot have a provider setting in interactive mode"
      end
    end

    def validate_openai_responses_api_compatibility
      # Check if any instance uses OpenAI provider with responses API
      responses_api_instances = @instances.select do |_name, instance|
        instance[:provider] == "openai" && instance[:api_version] == "responses"
      end

      return if responses_api_instances.empty?

      # Check ruby-openai version
      begin
        require "openai/version"
        openai_version = Gem::Version.new(::OpenAI::VERSION)
        required_version = Gem::Version.new("8.0.0")

        if openai_version < required_version
          instance_names = responses_api_instances.keys.join(", ")
          raise Error, "Instances #{instance_names} use OpenAI provider with api_version 'responses', which requires ruby-openai >= 8.0. Current version is #{openai_version}. Please update your Gemfile or run: gem install ruby-openai -v '>= 8.0'"
        end
      rescue LoadError
        # ruby-openai is not installed, which is fine - it will be caught later when trying to use it
      end
    end
  end
end
