# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Memory
      # Tool for reading content from memory storage
      #
      # Retrieves content stored by this agent using memory_write.
      # Each agent has its own isolated memory storage.
      class MemoryRead < RubyLLM::Tool
        define_method(:name) { "MemoryRead" }

        description <<~DESC
          Read content from your memory storage.
          Use this to retrieve detailed outputs, analysis, or results that were
          stored using memory_write. Only you (this agent) can access your memory.
        DESC

        param :file_path,
          desc: "Path to read from memory (e.g., 'analysis/report', 'parallel/batch1/task_0')",
          required: true

        class << self
          # Create a MemoryRead tool for a specific memory storage instance
          #
          # @param memory_storage [Stores::MemoryStorage] Per-agent memory storage instance
          # @param agent_name [Symbol, String] Agent identifier for tracking reads
          # @return [MemoryRead] Tool instance
          def create_for_memory(memory_storage, agent_name)
            new(memory_storage, agent_name)
          end
        end

        # Initialize with memory storage instance and agent name
        #
        # @param memory_storage [Stores::MemoryStorage] Per-agent memory storage instance
        # @param agent_name [Symbol, String] Agent identifier
        def initialize(memory_storage, agent_name)
          super() # Call RubyLLM::Tool's initialize
          @memory_storage = memory_storage
          @agent_name = agent_name.to_sym
        end

        # Execute the tool
        #
        # @param file_path [String] Path to read from
        # @return [String] Content at the path with line numbers, or error message
        def execute(file_path:)
          # Register this read in the tracker
          Stores::StorageReadTracker.register_read(@agent_name, file_path)

          content = memory_storage.read(file_path: file_path)
          format_with_line_numbers(content)
        rescue ArgumentError => e
          validation_error(e.message)
        end

        private

        attr_reader :memory_storage

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
end
