# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Tool for writing content to scratchpad memory
    #
    # Stores content in session-scoped, in-memory storage with metadata.
    # All agents in the swarm share the same scratchpad.
    class ScratchpadWrite < RubyLLM::Tool
      define_method(:name) { "ScratchpadWrite" }

      description <<~DESC
        Store content in scratchpad for later retrieval.
        Use this to save detailed outputs, analysis, or results that would
        otherwise bloat tool responses. Any agent can read this content using scratchpad_read.

        IMPORTANT: You must determine the appropriate file_path based on the task you're performing.
        Choose a logical, descriptive path that reflects the content type and purpose.
        Examples: 'analysis/code_review', 'research/findings', 'parallel/batch_1/results', 'logs/debug_trace'
      DESC

      param :file_path,
        desc: "File-path-like address you determine based on the task (e.g., 'analysis/report', 'parallel/batch1/task_0')",
        required: true

      param :content,
        desc: "Content to store in scratchpad (max 1MB per entry)",
        required: true

      param :title,
        desc: "Brief title describing the content (shown in listings)",
        required: true

      class << self
        # Create a ScratchpadWrite tool for a specific scratchpad instance
        #
        # @param scratchpad [Stores::Scratchpad] Shared scratchpad instance
        # @return [ScratchpadWrite] Tool instance
        def create_for_scratchpad(scratchpad)
          new(scratchpad)
        end
      end

      # Initialize with scratchpad instance
      #
      # @param scratchpad [Stores::Scratchpad] Shared scratchpad instance
      def initialize(scratchpad)
        super() # Call RubyLLM::Tool's initialize
        @scratchpad = scratchpad
      end

      # Execute the tool
      #
      # @param file_path [String] Path to store content
      # @param content [String] Content to store
      # @param title [String] Brief title
      # @return [String] Success message with path and size
      def execute(file_path:, content:, title:)
        entry = scratchpad.write(file_path: file_path, content: content, title: title)
        "Stored at scratchpad://#{file_path} (#{format_bytes(entry.size)})"
      rescue ArgumentError => e
        validation_error(e.message)
      end

      private

      attr_reader :scratchpad

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
