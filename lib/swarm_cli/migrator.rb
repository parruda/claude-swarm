# frozen_string_literal: true

module SwarmCLI
  # Migrator converts Claude Swarm v1 YAML configurations to SwarmSDK v2 format.
  #
  # Key transformations:
  # - version: 1 → 2
  # - swarm.main → swarm.lead
  # - swarm.instances → swarm.agents
  # - For each agent:
  #   - prompt → system_prompt
  #   - connections → delegates_to
  #   - mcps → mcp_servers
  #   - allowed_tools → tools
  #   - vibe → bypass_permissions
  #   - reasoning_effort → parameters.reasoning
  #
  class Migrator
    attr_reader :input_path

    def initialize(input_path)
      @input_path = input_path
    end

    def migrate
      # Read and parse v1 YAML
      v1_config = YAML.load_file(input_path)

      # Validate it's a v1 config
      unless v1_config["version"] == 1
        raise SwarmCLI::ExecutionError, "Input file is not a v1 configuration (version: #{v1_config["version"]})"
      end

      # Build v2 config
      v2_config = {
        "version" => 2,
        "swarm" => migrate_swarm(v1_config["swarm"]),
      }

      # Convert to YAML string
      YAML.dump(v2_config)
    end

    private

    def migrate_swarm(swarm)
      v2_swarm = {
        "name" => swarm["name"],
        "lead" => swarm["main"], # main → lead
      }

      # Migrate instances → agents
      if swarm["instances"]
        v2_swarm["agents"] = migrate_agents(swarm["instances"])
      end

      v2_swarm
    end

    def migrate_agents(instances)
      agents = {}

      instances.each do |name, config|
        agents[name] = migrate_agent(config)
      end

      agents
    end

    def migrate_agent(config)
      agent = {}

      # Copy fields that stay the same
      agent["description"] = config["description"] if config["description"]
      agent["directory"] = config["directory"] if config["directory"]
      agent["model"] = config["model"] if config["model"]

      # Migrate connections → delegates_to
      agent["delegates_to"] = if config["connections"]
        config["connections"]
      elsif config.key?("connections") && config["connections"].nil?
        # Explicit nil becomes empty array
        []
      else
        # No connections field - add empty array for clarity
        []
      end

      # Migrate prompt → system_prompt
      agent["system_prompt"] = config["prompt"] if config["prompt"]

      # Migrate mcps → mcp_servers
      if config["mcps"]
        agent["mcp_servers"] = config["mcps"]
      end

      # Migrate allowed_tools → tools
      if config["allowed_tools"]
        agent["tools"] = config["allowed_tools"]
      end

      # Migrate vibe → bypass_permissions
      if config["vibe"]
        agent["bypass_permissions"] = config["vibe"]
      end

      # Migrate reasoning_effort → parameters.reasoning
      if config["reasoning_effort"]
        agent["parameters"] ||= {}
        agent["parameters"]["reasoning"] = config["reasoning_effort"]
      end

      # Copy any other fields (like provider, base_url, etc. if they exist)
      # These are rare in v1 but handle them gracefully
      ["provider", "base_url", "api_version"].each do |field|
        agent[field] = config[field] if config[field]
      end

      # Handle parameters field - merge if it exists
      if config["parameters"]
        agent["parameters"] ||= {}
        agent["parameters"].merge!(config["parameters"])
      end

      # Copy tools and permissions if they exist (rare in v1)
      agent["tools"] = config["tools"] if config["tools"] && !config["allowed_tools"]
      agent["permissions"] = config["permissions"] if config["permissions"]

      agent
    end
  end
end
