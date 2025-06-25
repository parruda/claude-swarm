# frozen_string_literal: true

require "json"
require "fileutils"
require "shellwords"
require "securerandom"

module ClaudeSwarm
  class McpGenerator
    def initialize(configuration, vibe: false, restore_session_path: nil)
      @config = configuration
      @vibe = vibe
      @restore_session_path = restore_session_path
      @session_path = nil # Will be set when needed
      @instance_ids = {} # Store instance IDs for all instances
      @restore_states = {} # Store loaded state data during restoration
    end

    def generate_all
      ensure_swarm_directory

      if @restore_session_path
        # Load existing instance IDs and states from state files
        load_instance_states
      else
        # Generate new instance IDs
        @config.instances.each_key do |name|
          @instance_ids[name] = "#{name}_#{SecureRandom.hex(4)}"
        end
      end

      @config.instances.each do |name, instance|
        generate_mcp_config(name, instance)
      end
    end

    def mcp_config_path(instance_name)
      File.join(session_path, "#{instance_name}.mcp.json")
    end

    private

    def session_path
      @session_path ||= SessionPath.from_env
    end

    def ensure_swarm_directory
      # Session directory is already created by orchestrator
      # Just ensure it exists
      SessionPath.ensure_directory(session_path)
    end

    def generate_mcp_config(name, instance)
      mcp_servers = {}

      # Add configured MCP servers
      instance[:mcps].each do |mcp|
        mcp_servers[mcp["name"]] = build_mcp_server_config(mcp)
      end

      # Add connection MCPs for other instances
      instance[:connections].each do |connection_name|
        connected_instance = @config.instances[connection_name]
        mcp_servers[connection_name] = build_instance_mcp_config(
          connection_name, connected_instance,
          calling_instance: name, calling_instance_id: @instance_ids[name]
        )
      end

      config = {
        "instance_id" => @instance_ids[name],
        "instance_name" => name,
        "mcpServers" => mcp_servers
      }

      File.write(mcp_config_path(name), JSON.pretty_generate(config))
    end

    def build_mcp_server_config(mcp)
      case mcp["type"]
      when "stdio"
        {
          "type" => "stdio",
          "command" => mcp["command"],
          "args" => mcp["args"] || []
        }.tap do |config|
          config["env"] = mcp["env"] if mcp["env"]
        end
      when "sse"
        {
          "type" => "sse",
          "url" => mcp["url"]
        }
      end
    end

    def build_instance_mcp_config(name, instance, calling_instance:, calling_instance_id:)
      # Check if we should use llm-mcp for non-anthropic providers
      if instance[:provider] && instance[:provider] != "anthropic"
        build_llm_mcp_config(name, instance, calling_instance: calling_instance, calling_instance_id: calling_instance_id)
      else
        build_claude_swarm_config(name, instance, calling_instance: calling_instance, calling_instance_id: calling_instance_id)
      end
    end

    def build_llm_mcp_config(name, instance, calling_instance:, calling_instance_id:) # rubocop:disable Lint/UnusedMethodArgument
      # Build llm-mcp command
      args = [
        "mcp-serve",
        "--provider", instance[:provider],
        "--model", instance[:model]
      ]

      # Add base URL if specified
      args.push("--base-url", instance[:base_url]) if instance[:base_url]

      # Add temperature if specified
      args.push("--temperature", instance[:temperature].to_s) if instance[:temperature]

      # Always skip model validation to support custom models
      args.push("--skip-model-validation")

      # Add system prompt if specified
      args.push("--append-system-prompt", instance[:prompt]) if instance[:prompt]

      # Configure session management
      session_id = "#{@instance_ids[name]}_#{Time.now.strftime("%Y%m%d_%H%M%S")}"
      args.push("--session-id", session_id)
      args.push("--session-path", File.join(session_path, "llm_mcp_sessions"))

      # Configure logging to shared session log file
      args.push("--json-log-path", File.join(session_path, "session.log.json"))

      # Create MCP config for llm-mcp (includes connections, MCPs, and Claude tools)
      llm_mcp_config_path = File.join(session_path, "#{name}_llm_mcp_connections.json")
      generate_llm_mcp_connections(name, instance, llm_mcp_config_path)
      args.push("--mcp-config", llm_mcp_config_path)

      # Add verbose flag for debugging
      args.push("--verbose") if ENV["DEBUG"]

      config = {
        "type" => "stdio",
        "command" => "llm-mcp",
        "args" => args
      }

      # Add environment variables if needed
      env = {}
      case instance[:provider]
      when "openai"
        env["OPENAI_API_KEY"] = ENV["OPENAI_API_KEY"] if ENV["OPENAI_API_KEY"]
      when "google"
        env["GEMINI_API_KEY"] = ENV["GEMINI_API_KEY"] if ENV["GEMINI_API_KEY"]
        env["GOOGLE_API_KEY"] = ENV["GOOGLE_API_KEY"] if ENV["GOOGLE_API_KEY"]
      end

      config["env"] = env unless env.empty?
      config
    end

    def build_claude_swarm_config(name, instance, calling_instance:, calling_instance_id:)
      # Get the path to the claude-swarm executable
      exe_path = "claude-swarm"

      # Build command-line arguments for Thor
      args = [
        "mcp-serve",
        "--name", name,
        "--directory", instance[:directory],
        "--model", instance[:model]
      ]

      # Add directories array if we have multiple directories
      args.push("--directories", *instance[:directories]) if instance[:directories] && instance[:directories].size > 1

      # Add optional arguments
      args.push("--prompt", instance[:prompt]) if instance[:prompt]

      args.push("--description", instance[:description]) if instance[:description]

      args.push("--allowed-tools", instance[:allowed_tools].join(",")) if instance[:allowed_tools] && !instance[:allowed_tools].empty?

      args.push("--disallowed-tools", instance[:disallowed_tools].join(",")) if instance[:disallowed_tools] && !instance[:disallowed_tools].empty?

      args.push("--connections", instance[:connections].join(",")) if instance[:connections] && !instance[:connections].empty?

      args.push("--mcp-config-path", mcp_config_path(name))

      args.push("--calling-instance", calling_instance) if calling_instance

      args.push("--calling-instance-id", calling_instance_id) if calling_instance_id

      args.push("--instance-id", @instance_ids[name]) if @instance_ids[name]

      args.push("--vibe") if @vibe || instance[:vibe]

      # Add claude session ID if restoring
      if @restore_states[name.to_s]
        claude_session_id = @restore_states[name.to_s]["claude_session_id"]
        args.push("--claude-session-id", claude_session_id) if claude_session_id
      end

      {
        "type" => "stdio",
        "command" => exe_path,
        "args" => args
      }
    end

    def generate_llm_mcp_connections(name, instance, config_path)
      # Create MCP configuration for llm-mcp to connect to other instances
      mcp_servers = {}

      # Add configured MCP servers from the instance
      instance[:mcps].each do |mcp|
        mcp_servers[mcp["name"]] = build_mcp_server_config(mcp)
      end

      # Add connection MCPs for other instances
      instance[:connections].each do |connection_name|
        connected_instance = @config.instances[connection_name]
        # Generate MCP config for each connection
        mcp_servers[connection_name] = build_instance_mcp_config(
          connection_name, connected_instance,
          calling_instance: name, calling_instance_id: @instance_ids[name]
        )
      end

      # Add Claude MCP server for non-anthropic providers
      if instance[:provider] && instance[:provider] != "anthropic"
        mcp_servers["tools"] = {
          "type" => "stdio",
          "command" => "claude",
          "args" => %w[mcp serve]
        }
      end

      config = {
        "mcpServers" => mcp_servers
      }

      File.write(config_path, JSON.pretty_generate(config))
    end

    def load_instance_states
      state_dir = File.join(@restore_session_path, "state")
      return unless Dir.exist?(state_dir)

      Dir.glob(File.join(state_dir, "*.json")).each do |state_file|
        data = JSON.parse(File.read(state_file))
        instance_name = data["instance_name"]
        instance_id = data["instance_id"]

        # Check both string and symbol keys since config instances might have either
        if instance_name && (@config.instances.key?(instance_name) || @config.instances.key?(instance_name.to_sym))
          # Store with the same key type as in @config.instances
          key = @config.instances.key?(instance_name) ? instance_name : instance_name.to_sym
          @instance_ids[key] = instance_id
          @restore_states[instance_name] = data
        end
      rescue StandardError
        # Skip invalid state files
      end
    end
  end
end
