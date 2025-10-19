# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Memory
      # Tool for deleting content from memory storage
      #
      # Removes entries that are no longer relevant.
      # Each agent has its own isolated memory storage.
      class MemoryDelete < RubyLLM::Tool
        define_method(:name) { "MemoryDelete" }

        description <<~DESC
          Delete content from your memory when it's no longer relevant.
          Use this to remove outdated information, completed tasks, or data that's no longer needed.
          This helps keep your memory organized and prevents it from filling up.

          IMPORTANT: Only delete entries that are truly no longer needed. Once deleted, the content cannot be recovered.
        DESC

        param :file_path,
          desc: "Path to delete from memory (e.g., 'analysis/old_report', 'parallel/batch1/task_0')",
          required: true

        class << self
          # Create a MemoryDelete tool for a specific memory storage instance
          #
          # @param memory_storage [Stores::MemoryStorage] Per-agent memory storage instance
          # @return [MemoryDelete] Tool instance
          def create_for_memory(memory_storage)
            new(memory_storage)
          end
        end

        # Initialize with memory storage instance
        #
        # @param memory_storage [Stores::MemoryStorage] Per-agent memory storage instance
        def initialize(memory_storage)
          super() # Call RubyLLM::Tool's initialize
          @memory_storage = memory_storage
        end

        # Execute the tool
        #
        # @param file_path [String] Path to delete from
        # @return [String] Success message
        def execute(file_path:)
          memory_storage.delete(file_path: file_path)
          "Deleted memory://#{file_path}"
        rescue ArgumentError => e
          validation_error(e.message)
        end

        private

        attr_reader :memory_storage

        def validation_error(message)
          "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
        end
      end
    end
  end
end
