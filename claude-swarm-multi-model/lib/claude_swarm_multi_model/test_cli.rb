# frozen_string_literal: true

require "thor"

module ClaudeSwarmMultiModel
  # Test-friendly CLI that matches what the tests expect
  class CLI < Thor
    desc "version", "Show version"
    def version
      puts "claude-swarm-multi-model version #{ClaudeSwarmMultiModel::VERSION}"
    end

    desc "serve", "Start the MCP server"
    option :port, type: :numeric, desc: "Port to listen on"
    def serve
      require_relative "mcp/server"
      server = ClaudeSwarmMultiModel::Mcp::Server.new($stdin, $stdout, $stderr)
      server.start
    end

    desc "list-providers", "List available LLM providers"
    def list_providers
      providers = ClaudeSwarmMultiModel::ProviderRegistry.list_providers
      
      if providers.empty?
        puts "No providers available"
        return
      end
      
      puts "Available LLM Providers:"
      puts ""
      
      providers.each do |key, info|
        puts "#{key}:"
        puts "  Name: #{info[:name]}"
        puts "  Models: #{info[:models].join(", ")}"
        puts ""
      end
    end

    desc "validate-config FILE", "Validate a configuration file"
    def validate_config(file_path)
      unless File.exist?(file_path)
        $stderr.puts "Error: Configuration file not found: #{file_path}"
        exit 1
      end

      begin
        require "yaml"
        config = YAML.safe_load(File.read(file_path))
        
        # Basic validation
        providers = config["providers"] || {}
        
        puts "Configuration is valid"
        puts "Providers found: #{providers.keys.join(", ")}" unless providers.empty?
      rescue => e
        $stderr.puts "Configuration validation failed: #{e.message}"
        exit 1
      end
    end

    desc "detect-providers", "Detect available providers from environment"
    def detect_providers
      puts "Detecting available providers from environment..."
      puts ""
      
      available = ClaudeSwarmMultiModel::ProviderRegistry.detect_available_providers
      
      ClaudeSwarmMultiModel::ProviderRegistry::PROVIDERS.each do |key, _|
        if available.include?(key)
          puts "#{key}: Available"
        else
          puts "#{key}: Not configured"
        end
      end
    end
  end
end