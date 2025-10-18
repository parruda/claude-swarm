# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Stores
      # ScratchpadReadTracker manages read-entry tracking for all agents
      #
      # This module maintains a global registry of which scratchpad entries each agent
      # has read during their conversation. This enables enforcement of the
      # "read-before-edit" rule that ensures agents have context before modifying entries.
      #
      # Each agent maintains an independent set of read entries, keyed by agent identifier.
      module ScratchpadReadTracker
        @read_entries = {}
        @mutex = Mutex.new

        class << self
          # Register that an agent has read a scratchpad entry
          #
          # @param agent_id [Symbol] The agent identifier
          # @param entry_path [String] The scratchpad entry path
          def register_read(agent_id, entry_path)
            @mutex.synchronize do
              @read_entries[agent_id] ||= Set.new
              @read_entries[agent_id] << entry_path
            end
          end

          # Check if an agent has read a scratchpad entry
          #
          # @param agent_id [Symbol] The agent identifier
          # @param entry_path [String] The scratchpad entry path
          # @return [Boolean] true if the agent has read this entry
          def entry_read?(agent_id, entry_path)
            @mutex.synchronize do
              return false unless @read_entries[agent_id]

              @read_entries[agent_id].include?(entry_path)
            end
          end

          # Clear read history for an agent (useful for testing)
          #
          # @param agent_id [Symbol] The agent identifier
          def clear(agent_id)
            @mutex.synchronize do
              @read_entries.delete(agent_id)
            end
          end

          # Clear all read history (useful for testing)
          def clear_all
            @mutex.synchronize do
              @read_entries.clear
            end
          end
        end
      end
    end
  end
end
