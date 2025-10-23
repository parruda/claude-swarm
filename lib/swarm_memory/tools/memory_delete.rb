# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for deleting content from memory storage
    #
    # Removes entries that are no longer relevant.
    # Each agent has its own isolated memory storage.
    class MemoryDelete < RubyLLM::Tool
      description <<~DESC
        Delete entries from your memory storage when they're no longer needed.

        REQUIRED: Provide the file_path parameter - the path to the entry you want to delete.

        **Parameters:**
        - file_path (REQUIRED): Path to memory entry - MUST start with concept/, fact/, skill/, or experience/

        **MEMORY STRUCTURE (4 Fixed Categories Only):**
        - concept/{domain}/{name}.md - Abstract ideas
        - fact/{subfolder}/{name}.md - Concrete information
        - skill/{domain}/{name}.md - Procedures
        - experience/{name}.md - Lessons
        INVALID: documentation/, reference/, analysis/, parallel/, temp/, notes/

        **When to Delete:**
        - Outdated information that's been superseded
        - Completed tasks that are no longer relevant
        - Duplicate entries (after consolidating)
        - Test data or temporary calculations
        - Low-quality entries with minimal value

        **IMPORTANT WARNINGS:**
        - Deletion is PERMANENT - content cannot be recovered
        - Think carefully before deleting - consider if it might be useful later
        - Use MemoryDefrag to identify candidates for deletion (find_archival_candidates, compact)
        - Consider reading the entry first to verify you're deleting the right thing

        **Examples:**
        ```
        # Delete outdated concept
        MemoryDelete(file_path: "concept/old-api/deprecated.md")

        # Delete completed experience
        MemoryDelete(file_path: "experience/temp-experiment.md")

        # Delete obsolete fact
        MemoryDelete(file_path: "fact/orgs/defunct-company.md")
        ```

        **Best Practices:**
        1. Read entry first with MemoryRead to confirm it's the right one
        2. Use MemoryDefrag(action: "find_archival_candidates") to find old, unused entries
        3. Delete in batches during memory maintenance sessions
        4. Keep entries that might provide historical context
        5. Don't delete skills unless you're certain they won't be needed

        **Alternative to Deletion:**
        Instead of deleting, consider:
        - Updating entries to mark them as archived
        - Consolidating multiple entries into one comprehensive entry
        - Moving entries to an "archive/" hierarchy for later reference
      DESC

      param :file_path,
        desc: "Path to delete from memory - MUST start with concept/, fact/, skill/, or experience/ (e.g., 'concept/old-api/deprecated.md', 'experience/temp.md')",
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
