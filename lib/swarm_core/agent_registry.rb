# frozen_string_literal: true

module SwarmCore
  class AgentRegistry
    def initialize
      @agents = Concurrent::Hash.new
      @mutex = Mutex.new
    end

    def register(agent)
      @mutex.synchronize do
        if @agents.key?(agent.name)
          raise ConfigurationError, "Agent '#{agent.name}' is already registered"
        end

        @agents[agent.name] = agent
      end
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
      @mutex.synchronize do
        @agents.clear
      end
    end
  end
end
