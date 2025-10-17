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
        # @return [ScratchpadRead] Tool instance
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
      # @param file_path [String] Path to read from
      # @return [String] Content at the path or error message
      def execute(file_path:)
        scratchpad.read(file_path: file_path)
      rescue ArgumentError => e
        validation_error(e.message)
      end

      private

      attr_reader :scratchpad

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end
    end
  end
end
