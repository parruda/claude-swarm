# frozen_string_literal: true

require "yaml"
require "pathname"

module ClaudeSwarm
  class Configuration
    attr_reader :config, :swarm_name, :main_instance, :instances

    def initialize(config_path)
      @config_path = Pathname.new(config_path).expand_path
      @config_dir = @config_path.dirname
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
      swarm = @config["swarm"]
      @swarm_name = swarm["name"]
      @main_instance = swarm["main"]
      @instances = {}
      swarm["instances"].each do |name, config|
        @instances[name] = parse_instance(name, config)
      end
      validate_connections
    end

    def parse_instance(name, config)
      config ||= {}

      # Validate required fields
      raise Error, "Instance '#{name}' missing required 'description' field" unless config["description"]

      {
        name: name,
        directory: expand_path(config["directory"] || "."),
        model: config["model"] || "sonnet",
        connections: Array(config["connections"]),
        tools: Array(config["tools"]),
        mcps: parse_mcps(config["mcps"] || []),
        prompt: config["prompt"],
        description: config["description"]
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

    def validate_directories
      @instances.each do |name, instance|
        directory = instance[:directory]
        raise Error, "Directory '#{directory}' for instance '#{name}' does not exist" unless File.directory?(directory)
      end
    end

    def expand_path(path)
      Pathname.new(path).expand_path(@config_dir).to_s
    end
  end
end
