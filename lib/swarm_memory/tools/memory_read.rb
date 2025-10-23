# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for reading content from memory storage
    #
    # Retrieves content stored by this agent using memory_write.
    # Each agent has its own isolated memory storage.
    class MemoryRead < RubyLLM::Tool
      description <<~DESC
        Read content from your memory storage and retrieve all associated metadata.

        REQUIRED: Provide the file_path parameter - the path to the memory entry you want to read.

        **Parameters:**
        - file_path (REQUIRED): Path to memory entry - MUST start with concept/, fact/, skill/, or experience/

        **MEMORY STRUCTURE - EXACTLY 4 Top-Level Categories (NEVER create others):**
        ALL paths MUST start with one of these 4 fixed categories:
        - concept/{domain}/{name}.md - Abstract ideas (e.g., concept/ruby/classes.md)
        - fact/{subfolder}/{name}.md - Concrete info (e.g., fact/people/john.md)
        - skill/{domain}/{name}.md - Procedures (e.g., skill/debugging/api-errors.md)
        - experience/{name}.md - Lessons (e.g., experience/fixed-bug.md)

        INVALID: documentation/, reference/, tutorial/, parallel/, analysis/, notes/

        **Returns:**
        JSON with two fields:
        - content: Markdown content with line numbers (same format as Read tool)
        - metadata: All metadata (title, type, tags, tools, permissions, confidence, etc.)

        **Examples:**
        - MemoryRead(file_path: "concept/ruby/classes.md") - Read a concept
        - MemoryRead(file_path: "fact/people/john.md") - Read a fact
        - MemoryRead(file_path: "skill/debugging/api-errors.md") - Read a skill before loading it

        **Important:**
        - Always read entries before editing them with MemoryEdit or MemoryMultiEdit
        - Line numbers in output are for reference only - don't include them when editing
        - Each read is tracked to enforce read-before-edit patterns
      DESC

      param :file_path,
        desc: "Path to read from memory - MUST start with concept/, fact/, skill/, or experience/ (e.g., 'concept/ruby/classes.md', 'skill/debugging/api.md')",
        required: true

      # Initialize with storage instance and agent name
      #
      # @param storage [Core::Storage] Storage instance
      # @param agent_name [String, Symbol] Agent identifier
      def initialize(storage:, agent_name:)
        super()
        @storage = storage
        @agent_name = agent_name.to_sym
      end

      # Override name to return simple "MemoryRead"
      def name
        "MemoryRead"
      end

      # Execute the tool
      #
      # @param file_path [String] Path to read from
      # @return [String] JSON with content and metadata
      def execute(file_path:)
        # Register this read in the tracker
        Core::StorageReadTracker.register_read(@agent_name, file_path)

        # Read full entry with metadata
        entry = @storage.read_entry(file_path: file_path)

        # Always return JSON format (metadata always exists - at minimum title)
        format_as_json(entry)
      rescue ArgumentError => e
        validation_error(e.message)
      end

      private

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end

      # Format entry as JSON with content and metadata
      #
      # Returns a clean JSON format separating content from metadata.
      # This prevents agents from mimicking metadata format when writing.
      #
      # Content includes line numbers (same format as Read tool).
      # Metadata always includes at least title (from Entry).
      # Additional metadata comes from the metadata hash (type, tags, tools, etc.)
      #
      # @param entry [Core::Entry] Entry with content and metadata
      # @return [String] Pretty-printed JSON
      def format_as_json(entry)
        # Build metadata hash with title included
        metadata_hash = { "title" => entry.title }
        metadata_hash.merge!(entry.metadata) if entry.metadata

        result = {
          content: format_with_line_numbers(entry.content),
          metadata: metadata_hash,
        }
        JSON.pretty_generate(result)
      end

      # Format content with line numbers (same format as Read tool)
      #
      # @param content [String] Content to format
      # @return [String] Content with line numbers
      def format_with_line_numbers(content)
        lines = content.lines
        output_lines = lines.each_with_index.map do |line, idx|
          line_number = idx + 1
          display_line = line.chomp
          "#{line_number.to_s.rjust(6)}→#{display_line}"
        end
        output_lines.join("\n")
      end
    end
  end
end
