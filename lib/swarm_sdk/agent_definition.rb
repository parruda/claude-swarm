# frozen_string_literal: true

module SwarmSDK
  class AgentDefinition
    attr_reader :name,
      :description,
      :model,
      :directories,
      :tools,
      :delegates_to,
      :system_prompt,
      :provider,
      :temperature,
      :max_tokens,
      :base_url,
      :mcp_servers,
      :reasoning_effort

    def initialize(name, config = {})
      @name = name
      @description = config[:description]
      @model = config[:model] || "gpt-5"
      @system_prompt = config[:system_prompt]
      @provider = config[:provider] || "openai"
      @temperature = config[:temperature]
      @max_tokens = config[:max_tokens]
      @base_url = config[:base_url]
      @reasoning_effort = config[:reasoning_effort]

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
        temperature: @temperature,
        max_tokens: @max_tokens,
        base_url: @base_url,
        mcp_servers: @mcp_servers,
        reasoning_effort: @reasoning_effort,
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
