# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Memory
      # Tool for writing content to memory storage
      #
      # Stores content in persistent, per-agent memory storage with metadata.
      # Each agent has its own isolated memory storage that persists across sessions.
      class MemoryWrite < RubyLLM::Tool
        define_method(:name) { "MemoryWrite" }

        description <<~DESC
          Store content in memory for later retrieval.
          Use this to save detailed outputs, analysis, or results that would
          otherwise bloat tool responses. Only you (this agent) can access your memory.

          IMPORTANT: You must determine the appropriate file_path based on the task you're performing.
          Choose a logical, descriptive path that reflects the content type and purpose.
          Examples: 'analysis/code_review', 'research/findings', 'parallel/batch_1/results', 'logs/debug_trace'
        DESC

        param :file_path,
          desc: "File-path-like address you determine based on the task (e.g., 'analysis/report', 'parallel/batch1/task_0')",
          required: true

        param :content,
          desc: "Content to store in memory (max 1MB per entry)",
          required: true

        param :title,
          desc: "Brief title describing the content (shown in listings)",
          required: true

        class << self
          # Create a MemoryWrite tool for a specific memory storage instance
          #
          # @param memory_storage [Stores::MemoryStorage] Per-agent memory storage instance
          # @return [MemoryWrite] Tool instance
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
        # @param file_path [String] Path to store content
        # @param content [String] Content to store
        # @param title [String] Brief title
        # @return [String] Success message with path and size
        def execute(file_path:, content:, title:)
          entry = memory_storage.write(file_path: file_path, content: content, title: title)
          "Stored at memory://#{file_path} (#{format_bytes(entry.size)})"
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
