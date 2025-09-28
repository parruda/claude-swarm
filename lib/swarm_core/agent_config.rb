# frozen_string_literal: true

module SwarmCore
  class AgentConfig
    attr_reader :name,
      :description,
      :model,
      :directory,
      :directories,
      :tools,
      :connections,
      :prompt,
      :provider,
      :temperature,
      :max_tokens

    def initialize(name, config = {})
      @name = name
      @description = config["description"] || config[:description]
      @model = config["model"] || config[:model] || "claude-3-5-sonnet-20241022"
      @prompt = config["prompt"] || config[:prompt]
      @provider = config["provider"] || config[:provider]
      @temperature = config["temperature"] || config[:temperature]
      @max_tokens = config["max_tokens"] || config[:max_tokens]

      @directories = parse_directories(config["directory"] || config[:directory])
      @directory = @directories.first

      @tools = Array(config["tools"] || config[:tools] || [])
      @connections = Array(config["connections"] || config[:connections] || [])

      validate!
    end

    def to_h
      {
        name: @name,
        description: @description,
        model: @model,
        directory: @directory,
        directories: @directories,
        tools: @tools,
        connections: @connections,
        prompt: @prompt,
        provider: @provider,
        temperature: @temperature,
        max_tokens: @max_tokens,
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
      raise ConfigurationError, "Agent '#{@name}' missing required 'prompt' field" unless @prompt

      @directories.each do |dir|
        unless File.directory?(dir)
          raise ConfigurationError, "Directory '#{dir}' for agent '#{@name}' does not exist"
        end
      end
    end
  end
end
