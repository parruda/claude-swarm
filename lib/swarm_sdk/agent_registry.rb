# frozen_string_literal: true

module SwarmSDK
  class AgentRegistry
    def initialize
      @agents = Concurrent::Hash.new
    end

    def register(agent)
      if @agents.key?(agent.name)
        raise ConfigurationError, "Agent '#{agent.name}' is already registered"
      end

      @agents[agent.name] = agent
    end

    def get(name)
      agent = @agents[name]
      raise AgentNotFoundError, "Agent '#{name}' not found in registry" unless agent

      agent
    end

    def exists?(name)
      @agents.key?(name)
    end

    def all
      @agents.values
    end

    def count
      @agents.size
    end

    def names
      @agents.keys
    end

    def clear
      @agents.clear
    end
  end
end
