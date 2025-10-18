# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Tool for reading content from scratchpad memory
    #
    # Retrieves content stored by any agent using scratchpad_write.
    # All agents in the swarm share the same scratchpad.
    class ScratchpadRead < RubyLLM::Tool
      define_method(:name) { "ScratchpadRead" }

      description <<~DESC
        Read content from scratchpad.
        Use this to retrieve detailed outputs, analysis, or results that were
        stored using scratchpad_write. Any agent can read any scratchpad content.
      DESC

      param :file_path,
        desc: "Path to read from scratchpad (e.g., 'analysis/report', 'parallel/batch1/task_0')",
        required: true

      class << self
        # Create a ScratchpadRead tool for a specific scratchpad instance
        #
        # @param scratchpad [Stores::Scratchpad] Shared scratchpad instance
        # @param agent_name [Symbol, String] Agent identifier for tracking reads
        # @return [ScratchpadRead] Tool instance
        def create_for_scratchpad(scratchpad, agent_name)
          new(scratchpad, agent_name)
        end
      end

      # Initialize with scratchpad instance and agent name
      #
      # @param scratchpad [Stores::Scratchpad] Shared scratchpad instance
      # @param agent_name [Symbol, String] Agent identifier
      def initialize(scratchpad, agent_name)
        super() # Call RubyLLM::Tool's initialize
        @scratchpad = scratchpad
        @agent_name = agent_name.to_sym
      end

      # Execute the tool
      #
      # @param file_path [String] Path to read from
      # @return [String] Content at the path with line numbers, or error message
      def execute(file_path:)
        # Register this read in the tracker
        Stores::ScratchpadReadTracker.register_read(@agent_name, file_path)

        content = scratchpad.read(file_path: file_path)
        format_with_line_numbers(content)
      rescue ArgumentError => e
        validation_error(e.message)
      end

      private

      attr_reader :scratchpad

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
