# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Stores
      # TodoManager provides per-agent todo list storage
      #
      # Each agent maintains its own independent todo list that persists
      # throughout the agent's execution session. This allows agents to
      # track progress on complex multi-step tasks.
      class TodoManager
        @storage = {}
        @mutex = Mutex.new

        class << self
          # Get the current todo list for an agent
          #
          # @param agent_id [Symbol, String] Unique agent identifier
          # @return [Array<Hash>] Array of todo items
          def get_todos(agent_id)
            @mutex.synchronize do
              @storage[agent_id.to_sym] ||= []
            end
          end

          # Set the todo list for an agent
          #
          # @param agent_id [Symbol, String] Unique agent identifier
          # @param todos [Array<Hash>] Array of todo items
          # @return [Array<Hash>] The stored todos
          def set_todos(agent_id, todos)
            @mutex.synchronize do
              @storage[agent_id.to_sym] = todos
            end
          end

          # Clear all todos for an agent
          #
          # @param agent_id [Symbol, String] Unique agent identifier
          def clear_todos(agent_id)
            @mutex.synchronize do
              @storage.delete(agent_id.to_sym)
            end
          end

          # Clear all todos for all agents
          def clear_all
            @mutex.synchronize do
              @storage.clear
            end
          end

          # Get summary of all agent todo lists
          #
          # @return [Hash] Map of agent_id => todo count
          def summary
            @mutex.synchronize do
              @storage.transform_values(&:size)
            end
          end
        end
      end
    end
  end
end
