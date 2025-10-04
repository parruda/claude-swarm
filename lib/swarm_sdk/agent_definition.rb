# frozen_string_literal: true

module SwarmSDK
  class AgentDefinition
    DEFAULT_MODEL = "gpt-5"
    DEFAULT_PROVIDER = "openai"
    DEFAULT_TIMEOUT = 300 # 5 minutes - reasoning models can take a while

    attr_reader :name,
      :description,
      :model,
      :directories,
      :tools,
      :delegates_to,
      :system_prompt,
      :provider,
      :base_url,
      :mcp_servers,
      :parameters,
      :timeout

    def initialize(name, config = {})
      @name = name
      @description = config[:description]
      @model = config[:model] || DEFAULT_MODEL
      @system_prompt = config[:system_prompt]
      @provider = config[:provider] || DEFAULT_PROVIDER
      @base_url = config[:base_url]
      @parameters = config[:parameters] || {}
      @timeout = config[:timeout] || DEFAULT_TIMEOUT

      @directories = parse_directories(config[:directories])

      @tools = Array(config[:tools] || []).map(&:to_sym)
      @delegates_to = Array(config[:delegates_to] || []).map(&:to_sym)
      @mcp_servers = Array(config[:mcp_servers] || [])

      validate!
    end

    def to_h
      {
        name: @name,
        description: @description,
        model: @model,
        directories: @directories,
        tools: @tools,
        delegates_to: @delegates_to,
        system_prompt: @system_prompt,
        provider: @provider,
        base_url: @base_url,
        mcp_servers: @mcp_servers,
        parameters: @parameters,
        timeout: @timeout,
      }.compact
    end

    private

    def parse_directories(directory_config)
      directory_config ||= "."

      directories = Array(directory_config).map { |dir| File.expand_path(dir) }

      directories.empty? ? [File.expand_path(".")] : directories
    end

    def validate!
      raise ConfigurationError, "Agent '#{@name}' missing required 'description' field" unless @description
      raise ConfigurationError, "Agent '#{@name}' missing required 'system_prompt' field" unless @system_prompt

      @directories.each do |dir|
        unless File.directory?(dir)
          raise ConfigurationError, "Directory '#{dir}' for agent '#{@name}' does not exist"
        end
      end
    end
  end
end
