# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Stores
      # ReadTracker manages read-file tracking for all agents
      #
      # This module maintains a global registry of which files each agent has read
      # during their conversation. This enables enforcement of the "read-before-write"
      # and "read-before-edit" rules that ensure agents have context before modifying files.
      #
      # Each agent maintains an independent set of read files, keyed by agent identifier.
      module ReadTracker
        @read_files = {}
        @mutex = Mutex.new

        class << self
          # Register that an agent has read a file
          #
          # @param agent_id [Symbol] The agent identifier
          # @param file_path [String] The absolute path to the file
          def register_read(agent_id, file_path)
            @mutex.synchronize do
              @read_files[agent_id] ||= Set.new
              @read_files[agent_id] << File.expand_path(file_path)
            end
          end

          # Check if an agent has read a file
          #
          # @param agent_id [Symbol] The agent identifier
          # @param file_path [String] The absolute path to the file
          # @return [Boolean] true if the agent has read this file
          def file_read?(agent_id, file_path)
            @mutex.synchronize do
              return false unless @read_files[agent_id]

              @read_files[agent_id].include?(File.expand_path(file_path))
            end
          end

          # Clear read history for an agent (useful for testing)
          #
          # @param agent_id [Symbol] The agent identifier
          def clear(agent_id)
            @mutex.synchronize do
              @read_files.delete(agent_id)
            end
          end

          # Clear all read history (useful for testing)
          def clear_all
            @mutex.synchronize do
              @read_files.clear
            end
          end
        end
      end
    end
  end
end
