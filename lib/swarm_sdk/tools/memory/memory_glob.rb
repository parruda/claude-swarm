# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Memory
      # Tool for searching memory entries by glob pattern
      #
      # Finds memory entries matching a glob pattern (like filesystem glob).
      # Each agent has its own isolated memory storage.
      class MemoryGlob < RubyLLM::Tool
        define_method(:name) { "MemoryGlob" }

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

        class << self
          # Create a MemoryGlob tool for a specific memory storage instance
          #
          # @param memory_storage [Stores::MemoryStorage] Per-agent memory storage instance
          # @return [MemoryGlob] Tool instance
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
        # @param pattern [String] Glob pattern to match
        # @return [String] Formatted list of matching entries
        def execute(pattern:)
          entries = memory_storage.glob(pattern: pattern)

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

        attr_reader :memory_storage

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
end
