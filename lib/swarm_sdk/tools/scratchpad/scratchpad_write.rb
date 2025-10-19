# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Scratchpad
      # Tool for writing content to scratchpad storage
      #
      # Stores content in volatile, shared storage for temporary communication.
      # All agents in the swarm share the same scratchpad.
      # Data is lost when the process ends (not persisted).
      class ScratchpadWrite < RubyLLM::Tool
        define_method(:name) { "ScratchpadWrite" }

        description <<~DESC
          Store content in scratchpad for temporary cross-agent communication.
          Use this for quick notes, intermediate results, or coordination messages.
          Any agent can read this content. Data is lost when the swarm ends.

          For persistent storage that survives across sessions, use MemoryWrite instead.

          Choose a simple, descriptive path. Examples: 'status', 'result', 'notes/agent_x'
        DESC

        param :file_path,
          desc: "Simple path for the content (e.g., 'status', 'result', 'notes/agent_x')",
          required: true

        param :content,
          desc: "Content to store in scratchpad (max 1MB per entry)",
          required: true

        param :title,
          desc: "Brief title describing the content",
          required: true

        class << self
          # Create a ScratchpadWrite tool for a specific scratchpad storage instance
          #
          # @param scratchpad_storage [Stores::ScratchpadStorage] Shared scratchpad storage instance
          # @return [ScratchpadWrite] Tool instance
          def create_for_scratchpad(scratchpad_storage)
            new(scratchpad_storage)
          end
        end

        # Initialize with scratchpad storage instance
        #
        # @param scratchpad_storage [Stores::ScratchpadStorage] Shared scratchpad storage instance
        def initialize(scratchpad_storage)
          super() # Call RubyLLM::Tool's initialize
          @scratchpad_storage = scratchpad_storage
        end

        # Execute the tool
        #
        # @param file_path [String] Path to store content
        # @param content [String] Content to store
        # @param title [String] Brief title
        # @return [String] Success message with path and size
        def execute(file_path:, content:, title:)
          entry = scratchpad_storage.write(file_path: file_path, content: content, title: title)
          "Stored at scratchpad://#{file_path} (#{format_bytes(entry.size)})"
        rescue ArgumentError => e
          validation_error(e.message)
        end

        private

        attr_reader :scratchpad_storage

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
