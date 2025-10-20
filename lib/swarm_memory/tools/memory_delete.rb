# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for deleting content from memory storage
    #
    # Removes entries that are no longer relevant.
    # Each agent has its own isolated memory storage.
    class MemoryDelete < RubyLLM::Tool
      description <<~DESC
        Delete content from your memory when it's no longer relevant.
        Use this to remove outdated information, completed tasks, or data that's no longer needed.
        This helps keep your memory organized and prevents it from filling up.

        IMPORTANT: Only delete entries that are truly no longer needed. Once deleted, the content cannot be recovered.
      DESC

      param :file_path,
        desc: "Path to delete from memory (e.g., 'analysis/old_report', 'parallel/batch1/task_0')",
        required: true

      # Initialize with storage instance
      #
      # @param storage [Core::Storage] Storage instance
      def initialize(storage:)
        super()
        @storage = storage
      end

      # Override name to return simple "MemoryDelete"
      def name
        "MemoryDelete"
      end

      # Execute the tool
      #
      # @param file_path [String] Path to delete from
      # @return [String] Success message
      def execute(file_path:)
        @storage.delete(file_path: file_path)
        "Deleted memory://#{file_path}"
      rescue ArgumentError => e
        validation_error(e.message)
      end

      private

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end
    end
  end
end
