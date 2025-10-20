# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for reading content from memory storage
    #
    # Retrieves content stored by this agent using memory_write.
    # Each agent has its own isolated memory storage.
    class MemoryRead < RubyLLM::Tool
      description <<~DESC
        Read content from your memory storage.
        Use this to retrieve detailed outputs, analysis, or results that were
        stored using memory_write. Only you (this agent) can access your memory.
      DESC

      param :file_path,
        desc: "Path to read from memory (e.g., 'analysis/report', 'parallel/batch1/task_0')",
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
      # @return [String] Content at the path with line numbers, or error message
      def execute(file_path:)
        # Register this read in the tracker
        Core::StorageReadTracker.register_read(@agent_name, file_path)

        content = @storage.read(file_path: file_path)
        format_with_line_numbers(content)
      rescue ArgumentError => e
        validation_error(e.message)
      end

      private

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
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
