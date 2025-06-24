# frozen_string_literal: true

require "yaml"
require "pathname"

module ClaudeSwarm
  class Configuration
    attr_reader :config, :config_path, :swarm, :swarm_name, :main_instance, :instances

    def initialize(config_path, base_dir: nil)
      @config_path = Pathname.new(config_path).expand_path
      @config_dir = @config_path.dirname
      @base_dir = base_dir || @config_dir
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

    private

    def load_and_validate
      @config = YAML.load_file(@config_path)
      validate_version
      validate_swarm
      parse_swarm
      validate_directories
    rescue Errno::ENOENT
      raise Error, "Configuration file not found: #{@config_path}"
    rescue Psych::SyntaxError => e
      raise Error, "Invalid YAML syntax: #{e.message}"
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
      validate_connections
      detect_circular_dependencies
    end

    def parse_instance(name, config)
      config ||= {}

      # Validate required fields
      raise Error, "Instance '#{name}' missing required 'description' field" unless config["description"]

      # Validate tool fields are arrays if present
      validate_tool_field(name, config, "tools")
      validate_tool_field(name, config, "allowed_tools")
      validate_tool_field(name, config, "disallowed_tools")

      # Support both 'tools' (deprecated) and 'allowed_tools' for backward compatibility
      allowed_tools = config["allowed_tools"] || config["tools"] || []

      # Parse directory field - support both string and array
      directories = parse_directories(config["directory"])

      {
        name: name,
        directory: directories.first, # Keep single directory for backward compatibility
        directories: directories, # New field with all directories
        model: config["model"] || "sonnet",
        provider: config["provider"], # New field for LLM provider
        base_url: config["base_url"], # New field for custom API base URL
        connections: Array(config["connections"]),
        tools: Array(allowed_tools), # Keep as 'tools' internally for compatibility
        allowed_tools: Array(allowed_tools),
        disallowed_tools: Array(config["disallowed_tools"]),
        mcps: parse_mcps(config["mcps"] || []),
        prompt: config["prompt"],
        description: config["description"],
        vibe: config["vibe"] || false,
        worktree: parse_worktree_value(config["worktree"])
      }
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
      when "sse"
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

    def validate_directories
      @instances.each do |name, instance|
        # Validate all directories in the directories array
        instance[:directories].each do |directory|
          raise Error, "Directory '#{directory}' for instance '#{name}' does not exist" unless File.directory?(directory)
        end
      end
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
      return nil if value.nil? # Omitted means follow CLI behavior
      return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)
      return value.to_s if value.is_a?(String) && !value.empty?

      raise Error, "Invalid worktree value: #{value.inspect}. Must be true, false, or a non-empty string"
    end
  end
end
