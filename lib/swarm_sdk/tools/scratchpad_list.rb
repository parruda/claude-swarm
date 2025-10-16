# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Tool for listing scratchpad entries with metadata
    #
    # Lists available scratchpad entries with titles and sizes.
    # Supports filtering by path prefix.
    class ScratchpadList < RubyLLM::Tool
      define_method(:name) { "ScratchpadList" }

      description <<~DESC
        List available scratchpad entries with titles and metadata.
        Use this to discover what content is available in scratchpad memory.
        Optionally filter by path prefix.
      DESC

      param :prefix,
        desc: "Filter by path prefix (e.g., 'parallel/', 'analysis/'). Leave empty to list all entries.",
        required: false

      class << self
        # Create a ScratchpadList tool for a specific scratchpad instance
        #
        # @param scratchpad [Stores::Scratchpad] Shared scratchpad instance
        # @return [ScratchpadList] Tool instance
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
      # @param prefix [String, nil] Optional path prefix filter
      # @return [String] Formatted list of entries
      def execute(prefix: nil)
        entries = scratchpad.list(prefix: prefix)

        if entries.empty?
          return "Scratchpad is empty" if prefix.nil? || prefix.empty?

          return "No entries found with prefix '#{prefix}'"
        end

        result = []
        result << "Scratchpad contents (#{entries.size} #{entries.size == 1 ? "entry" : "entries"}):"

        entries.each do |entry|
          result << "  scratchpad://#{entry[:path]} - \"#{entry[:title]}\" (#{format_bytes(entry[:size])})"
        end

        result.join("\n")
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
