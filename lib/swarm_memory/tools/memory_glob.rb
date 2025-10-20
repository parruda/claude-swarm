# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for searching memory entries by glob pattern
    #
    # Finds memory entries matching a glob pattern (like filesystem glob).
    # Each agent has its own isolated memory storage.
    class MemoryGlob < RubyLLM::Tool
      description <<~DESC
        Search your memory entries by glob pattern.
        Works like filesystem glob - use * for wildcards, ** for recursive matching.
        Use this to discover entries matching specific patterns.

        Examples:
        - "parallel/*" - all entries directly under parallel/
        - "parallel/**" - all entries under parallel/ (recursive)
        - "*/report" - all entries named "report" in any top-level directory
        - "analysis/*/result_*" - entries like "analysis/foo/result_1"
      DESC

      param :pattern,
        desc: "Glob pattern to match (e.g., '**/*.txt', 'parallel/*/task_*')",
        required: true

      # Initialize with storage instance
      #
      # @param storage [Core::Storage] Storage instance
      def initialize(storage:)
        super()
        @storage = storage
      end

      # Override name to return simple "MemoryGlob"
      def name
        "MemoryGlob"
      end

      # Execute the tool
      #
      # @param pattern [String] Glob pattern to match
      # @return [String] Formatted list of matching entries
      def execute(pattern:)
        entries = @storage.glob(pattern: pattern)

        if entries.empty?
          return "No entries found matching pattern '#{pattern}'"
        end

        result = []
        result << "Memory entries matching '#{pattern}' (#{entries.size} #{entries.size == 1 ? "entry" : "entries"}):"

        entries.each do |entry|
          result << "  memory://#{entry[:path]} - \"#{entry[:title]}\" (#{format_bytes(entry[:size])})"
        end

        result.join("\n")
      rescue ArgumentError => e
        validation_error(e.message)
      end

      private

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end

      # Format bytes to human-readable size
      #
      # @param bytes [Integer] Number of bytes
      # @return [String] Formatted size
      def format_bytes(bytes)
        if bytes >= 1_000_000
          "#{(bytes.to_f / 1_000_000).round(1)}MB"
        elsif bytes >= 1_000
          "#{(bytes.to_f / 1_000).round(1)}KB"
        else
          "#{bytes}B"
        end
      end
    end
  end
end
