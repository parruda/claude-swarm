# frozen_string_literal: true

require "thor"
require "json"
require_relative "config_validator"

module ClaudeSwarmMultiModel
  class CLI < Thor
    def self.register_commands(cli_class)
      cli_class.desc "llm-serve", "Start an MCP server for a specific LLM provider"
      cli_class.option :provider, type: :string, required: true, enum: %w[openai gemini groq deepseek together local],
                                  desc: "LLM provider to use"
      cli_class.option :model, type: :string, required: true,
                               desc: "Model name to use with the provider"
      cli_class.option :api_key_env, type: :string,
                                     desc: "Environment variable containing the API key"
      cli_class.option :base_url_env, type: :string,
                                      desc: "Environment variable containing the base URL (optional)"
      cli_class.option :append_system_prompt, type: :string,
                                              desc: "Additional system prompt to append"

      cli_class.define_method(:llm_serve) do
        extension_available = begin
          require "claude_swarm_multi_model"
          true
        rescue LoadError
          false
        end

        unless extension_available
          error_message = <<~ERROR
            Error: claude-swarm-multi-model gem is not installed.

            To use multi-model support, install the gem:
              gem install claude-swarm-multi-model

            Or add to your Gemfile:
              gem 'claude-swarm-multi-model'
          ERROR

          say error_message, :red
          exit 1
        end

        ClaudeSwarmMultiModel::CLI.new.llm_serve(options)
      end

      # Register list-providers command
      cli_class.desc "list-providers", "List available LLM providers and their models"
      cli_class.define_method(:list_providers) do
        extension_available = begin
          require "claude_swarm_multi_model"
          true
        rescue LoadError
          false
        end

        unless extension_available
          say "Error: claude-swarm-multi-model gem is not installed.", :red
          exit 1
        end

        ClaudeSwarmMultiModel::CLI.new.list_providers
      end
    end

    desc "llm-serve", "Start an MCP server for a specific LLM provider"
    option :provider, type: :string, required: true, enum: %w[openai gemini groq deepseek together local],
                      desc: "LLM provider to use"
    option :model, type: :string, required: true,
                   desc: "Model name to use with the provider"
    option :api_key_env, type: :string,
                         desc: "Environment variable containing the API key"
    option :base_url_env, type: :string,
                          desc: "Environment variable containing the base URL (optional)"
    option :append_system_prompt, type: :string,
                                  desc: "Additional system prompt to append"

    def llm_serve
      validate_environment!

      server_options = {
        provider: options[:provider],
        model: options[:model],
        api_key_env: options[:api_key_env],
        base_url_env: options[:base_url_env],
        append_system_prompt: options[:append_system_prompt]
      }.compact

      # Start the MCP server
      unless defined?(ClaudeSwarmMultiModel::MCP::Server)
        say "Error: MCP server components are not available. Please install fast_mcp gem.", :red
        exit 1
      end

      server = ClaudeSwarmMultiModel::MCP::Server.new(server_options)
      server.run
    rescue StandardError => e
      say "Error starting MCP server: #{e.message}", :red
      say e.backtrace.join("\n"), :red if options[:debug]
      exit 1
    end

    desc "list-providers", "List available LLM providers and their models"
    def list_providers
      say "Available LLM Providers:", :green
      say ""

      ConfigValidator::PROVIDERS.each do |name, info|
        # Skip anthropic as it's handled natively by Claude Swarm
        next if name == "anthropic"

        say "#{name}:", :yellow
        say "  API Key: #{info[:api_key_env] || "Not required"}"

        if info[:models].is_a?(Array)
          say "  Models:"
          info[:models].each { |model| say "    - #{model}" }
        else
          say "  Models: Any model supported by the provider"
        end

        say "  Base URL: Set via #{info[:base_url_env]}" if info[:base_url_env]

        say ""
      end
    end

    private

    def validate_environment!
      # Validate API key environment variable if specified
      if options[:api_key_env] && !ENV.fetch(options[:api_key_env], nil)
        say "Error: Environment variable '#{options[:api_key_env]}' is not set", :red
        exit 1
      end

      # Validate base URL environment variable if specified
      if options[:base_url_env] && !ENV.fetch(options[:base_url_env], nil)
        say "Warning: Environment variable '#{options[:base_url_env]}' is not set", :yellow
      end

      # Check for ruby_llm dependency
      begin
        require "ruby_llm"
      rescue LoadError
        say "Error: ruby_llm gem is required but not installed", :red
        say "Please install it: gem install ruby_llm", :red
        exit 1
      end
    end
  end
end
