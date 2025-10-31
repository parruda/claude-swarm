# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Scratchpad
      # Tool for listing scratchpad entries
      #
      # Shows all entries in the shared scratchpad with their metadata.
      # All agents in the swarm share the same scratchpad.
      class ScratchpadList < RubyLLM::Tool
        define_method(:name) { "ScratchpadList" }

        description <<~DESC
          List all entries in scratchpad with their metadata.

          ## When to Use ScratchpadList

          Use ScratchpadList to:
          - Discover what content is available in the scratchpad
          - Check what other agents have stored
          - Find relevant entries before reading them
          - Review all stored outputs and analysis
          - Check entry sizes and last update times

          ## Best Practices

          - Use this before ScratchpadRead if you don't know what's stored
          - Filter by prefix to narrow down results (e.g., 'notes/' lists all notes)
          - Shows path, title, size, and last updated time for each entry
          - Any agent can see all scratchpad entries
          - Helps coordinate multi-agent workflows

          ## Examples

          - List all entries: (no prefix parameter)
          - List notes only: prefix='notes/'
          - List analysis results: prefix='analysis/'
        DESC

        param :prefix,
          desc: "Optional prefix to filter entries (e.g., 'notes/' to list all entries under notes/)",
          required: false

        class << self
          # Create a ScratchpadList tool for a specific scratchpad storage instance
          #
          # @param scratchpad_storage [Stores::ScratchpadStorage] Shared scratchpad storage instance
          # @return [ScratchpadList] Tool instance
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
        # @param prefix [String, nil] Optional prefix to filter entries
        # @return [String] Formatted list of entries
        def execute(prefix: nil)
          entries = scratchpad_storage.list(prefix: prefix)

          if entries.empty?
            prefix_msg = prefix ? " with prefix '#{prefix}'" : ""
            return "No entries found in scratchpad#{prefix_msg}"
          end

          result = []
          prefix_msg = prefix ? " with prefix '#{prefix}'" : ""
          result << "Scratchpad entries#{prefix_msg} (#{entries.size} #{entries.size == 1 ? "entry" : "entries"}):"
          result << ""

          entries.each do |entry|
            time_str = entry[:updated_at].strftime("%Y-%m-%d %H:%M:%S")
            result << "  scratchpad://#{entry[:path]}"
            result << "    Title: #{entry[:title]}"
            result << "    Size: #{format_bytes(entry[:size])}"
            result << "    Updated: #{time_str}"
            result << ""
          end

          result.join("\n").rstrip
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
