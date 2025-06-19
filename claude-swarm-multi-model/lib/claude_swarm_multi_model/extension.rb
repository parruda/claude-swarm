# frozen_string_literal: true

# Only require claude_swarm if it's available
begin
  require "claude_swarm"
rescue LoadError
  # Extension will be loaded when claude_swarm is available
end

module ClaudeSwarmMultiModel
  module Extension
    def self.register!
      # Only register if ClaudeSwarm is available
      return unless defined?(ClaudeSwarm::Extensions)

      # Register the extension with claude-swarm
      ClaudeSwarm::Extensions.register_extension("claude-swarm-multi-model", {
                                                   name: "Claude Swarm Multi-Model Support",
                                                   version: VERSION,
                                                   description: "Enables orchestration of AI agents across different model providers"
                                                 })

      # Register configuration hooks
      ClaudeSwarm::Extensions.register_hook(:after_parse_config, priority: 100) do |config|
        ConfigValidator.process_config(config)
      end

      ClaudeSwarm::Extensions.register_hook(:validate_instance, priority: 100) do |instance, instance_config|
        ConfigValidator.validate_instance(instance, instance_config)
      end

      # Register MCP generation hooks
      ClaudeSwarm::Extensions.register_hook(:modify_mcp_server, priority: 100) do |server_config, _instance_name, instance_config|
        if instance_config["provider"] && instance_config["provider"] != "anthropic"
          modify_mcp_server_for_provider(server_config, instance_config)
        else
          server_config
        end
      end

      # Register CLI hooks
      ClaudeSwarm::Extensions.register_hook(:register_commands, priority: 100) do |cli_class|
        CLI.register_commands(cli_class)
      end

      # Register orchestrator hooks
      ClaudeSwarm::Extensions.register_hook(:before_launch_swarm, priority: 100) do |orchestrator|
        setup_multi_model_environment(orchestrator)
      end
    end

    def self.modify_mcp_server_for_provider(server_config, instance_config)
      # Replace the command with our llm-serve command
      provider = instance_config["provider"]
      model = instance_config["model"]

      command = [
        "claude-swarm-llm-mcp",
        "--provider", provider
      ]

      command.push("--model", model) if model

      # Add optional command line arguments
      command.push("--api-key-env", instance_config["api_key_env"]) if instance_config["api_key_env"]

      command.push("--base-url-env", instance_config["base_url_env"]) if instance_config["base_url_env"]

      command.push("--system-prompt", instance_config["prompt"]) if instance_config["prompt"]

      command.push("--temperature", instance_config["temperature"].to_s) if instance_config["temperature"]

      server_config["command"] = command

      # Add environment variables if needed
      if instance_config["api_key_env"]
        server_config["env"] ||= {}
        env_var = instance_config["api_key_env"]
        server_config["env"][env_var] = ENV[env_var] if ENV[env_var]
      end

      # Add base URL if specified
      if instance_config["base_url_env"]
        server_config["env"] ||= {}
        env_var = instance_config["base_url_env"]
        server_config["env"][env_var] = ENV[env_var] if ENV[env_var]
      end

      server_config
    end

    def self.setup_multi_model_environment(_orchestrator)
      # Set up any necessary environment for multi-model support
      # This could include validating ruby_llm is available, etc.
      require "ruby_llm"
    rescue LoadError
      raise Error, "ruby_llm gem is required for multi-model support. Please install it."
    end
  end
end
