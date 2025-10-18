# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Tool for searching scratchpad content by pattern
    #
    # Searches content stored in scratchpad entries using regex patterns.
    # All agents in the swarm share the same scratchpad.
    class ScratchpadGrep < RubyLLM::Tool
      define_method(:name) { "ScratchpadGrep" }

      description <<~DESC
        Search scratchpad content by pattern (like grep).
        Use regex patterns to search content within scratchpad entries.
        Returns matching entries and optionally line numbers and content.

        Output modes:
        - files_with_matches: Only list paths containing matches (default)
        - content: Show matching lines with line numbers
        - count: Show number of matches per file
      DESC

      param :pattern,
        desc: "Regular expression pattern to search for",
        required: true

      param :case_insensitive,
        desc: "Perform case-insensitive search (default: false)",
        required: false

      param :output_mode,
        desc: "Output mode: 'files_with_matches' (default), 'content', or 'count'",
        required: false

      class << self
        # Create a ScratchpadGrep tool for a specific scratchpad instance
        #
        # @param scratchpad [Stores::Scratchpad] Shared scratchpad instance
        # @return [ScratchpadGrep] Tool instance
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
      # @param pattern [String] Regex pattern to search for
      # @param case_insensitive [Boolean] Whether to perform case-insensitive search
      # @param output_mode [String] Output mode
      # @return [String] Formatted search results
      def execute(pattern:, case_insensitive: false, output_mode: "files_with_matches")
        results = scratchpad.grep(
          pattern: pattern,
          case_insensitive: case_insensitive,
          output_mode: output_mode,
        )

        format_results(results, pattern, output_mode)
      rescue ArgumentError => e
        validation_error(e.message)
      rescue RegexpError => e
        validation_error("Invalid regex pattern: #{e.message}")
      end

      private

      attr_reader :scratchpad

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end

      def format_results(results, pattern, output_mode)
        case output_mode
        when "files_with_matches"
          format_files_with_matches(results, pattern)
        when "content"
          format_content(results, pattern)
        when "count"
          format_count(results, pattern)
        else
          validation_error("Invalid output_mode: #{output_mode}")
        end
      end

      def format_files_with_matches(paths, pattern)
        if paths.empty?
          return "No matches found for pattern '#{pattern}'"
        end

        result = []
        result << "Scratchpad entries matching '#{pattern}' (#{paths.size} #{paths.size == 1 ? "entry" : "entries"}):"
        paths.each do |path|
          result << "  scratchpad://#{path}"
        end
        result.join("\n")
      end

      def format_content(results, pattern)
        if results.empty?
          return "No matches found for pattern '#{pattern}'"
        end

        total_matches = results.sum { |r| r[:matches].size }
        output = []
        output << "Scratchpad entries matching '#{pattern}' (#{results.size} #{results.size == 1 ? "entry" : "entries"}, #{total_matches} #{total_matches == 1 ? "match" : "matches"}):"
        output << ""

        results.each do |result|
          output << "scratchpad://#{result[:path]}:"
          result[:matches].each do |match|
            output << "  #{match[:line_number]}: #{match[:content]}"
          end
          output << ""
        end

        output.join("\n").rstrip
      end

      def format_count(results, pattern)
        if results.empty?
          return "No matches found for pattern '#{pattern}'"
        end

        total_matches = results.sum { |r| r[:count] }
        output = []
        output << "Scratchpad entries matching '#{pattern}' (#{results.size} #{results.size == 1 ? "entry" : "entries"}, #{total_matches} total #{total_matches == 1 ? "match" : "matches"}):"

        results.each do |result|
          output << "  scratchpad://#{result[:path]}: #{result[:count]} #{result[:count] == 1 ? "match" : "matches"}"
        end

        output.join("\n")
      end
    end
  end
end
