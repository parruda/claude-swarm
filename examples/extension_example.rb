# frozen_string_literal: true

# Example extension for claude-swarm demonstrating how to use the extension hooks
# This file would typically be placed in ~/.claude-swarm/extensions.rb or
# in the project's .claude-swarm/extensions.rb

# Register this extension
ClaudeSwarm::Extensions.register_extension("example_extension", {
  version: "1.0.0",
  description: "Example extension demonstrating hook usage"
})

# Hook: Before parsing configuration
# This can modify the raw YAML configuration before it's parsed
ClaudeSwarm::Extensions.register_hook(ClaudeSwarm::ExtensionHooks::BEFORE_PARSE_CONFIG) do |config, config_path|
  puts "[Extension] Processing configuration from: #{config_path}" if ENV["DEBUG_EXTENSIONS"]
  
  # Example: Add a default model if not specified
  if config["swarm"] && config["swarm"]["instances"]
    config["swarm"]["instances"].each do |name, instance|
      instance["model"] ||= "haiku" # Default to haiku if not specified
    end
  end
  
  config # Return the potentially modified config
end

# Hook: Validate instance configuration
# This can validate custom fields added by extensions
ClaudeSwarm::Extensions.register_hook(ClaudeSwarm::ExtensionHooks::VALIDATE_INSTANCE) do |name, config|
  # Example: Validate a custom field if present
  if config["custom_field"] && !config["custom_field"].is_a?(String)
    raise ClaudeSwarm::Error, "Instance '#{name}' has invalid custom_field - must be a string"
  end
  
  nil # Return nil to not modify the result
end

# Hook: Modify MCP configuration
# This can add additional MCP servers or modify the configuration
ClaudeSwarm::Extensions.register_hook(ClaudeSwarm::ExtensionHooks::MODIFY_MCP_CONFIG) do |config, name, instance|
  puts "[Extension] Modifying MCP config for instance: #{name}" if ENV["DEBUG_EXTENSIONS"]
  
  # Example: Add a custom MCP server for specific instances
  if instance[:name] == "frontend_dev"
    config["mcpServers"]["custom_tool"] = {
      "type" => "stdio",
      "command" => "custom-mcp-server",
      "args" => ["--instance", name]
    }
  end
  
  config # Return the modified config
end

# Hook: Before launching the swarm
# This can perform setup tasks before the swarm starts
ClaudeSwarm::Extensions.register_hook(ClaudeSwarm::ExtensionHooks::BEFORE_LAUNCH_SWARM) do |config|
  puts "[Extension] Preparing to launch swarm: #{config.swarm_name}" if ENV["DEBUG_EXTENSIONS"]
  
  # Example: Create a temporary directory for the swarm
  swarm_temp_dir = "/tmp/claude-swarm-#{config.swarm_name.gsub(/\s+/, '-').downcase}"
  FileUtils.mkdir_p(swarm_temp_dir) unless Dir.exist?(swarm_temp_dir)
  
  nil # Return nil to not modify the result
end

# Hook: Register custom CLI commands
# This allows extensions to add new commands to the CLI
ClaudeSwarm::Extensions.register_hook(ClaudeSwarm::ExtensionHooks::REGISTER_COMMANDS) do |cli_class|
  # Skip if we're being called during method_added (second parameter would be the method name)
  next if cli_class.is_a?(Symbol)
  
  # Define a custom command on the CLI class
  cli_class.class_eval do
    desc "custom-command", "Example custom command from extension"
    def custom_command
      say "This is a custom command added by the example extension!", :green
      say "It demonstrates how extensions can add new CLI commands."
    end
  end
  
  nil # Return nil to not modify the result
end

# Hook: After swarm completes
# This can perform cleanup or reporting tasks
ClaudeSwarm::Extensions.register_hook(ClaudeSwarm::ExtensionHooks::AFTER_SWARM_COMPLETE) do |config|
  puts "[Extension] Swarm completed: #{config.swarm_name}" if ENV["DEBUG_EXTENSIONS"]
  
  # Example: Log completion time
  completion_time = Time.now
  log_file = "/tmp/claude-swarm-completions.log"
  File.open(log_file, "a") do |f|
    f.puts "[#{completion_time}] Swarm '#{config.swarm_name}' completed"
  end
  
  nil # Return nil to not modify the result
end

puts "[Extension] Example extension loaded successfully!" if ENV["DEBUG_EXTENSIONS"]