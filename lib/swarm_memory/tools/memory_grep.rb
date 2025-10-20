# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for searching memory content by pattern
    #
    # Searches content stored in memory entries using regex patterns.
    # Each agent has its own isolated memory storage.
    class MemoryGrep < RubyLLM::Tool
      description <<~DESC
        Search your memory content by pattern (like grep).
        Use regex patterns to search content within memory entries.
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

      # Initialize with storage instance
      #
      # @param storage [Core::Storage] Storage instance
      def initialize(storage:)
        super()
        @storage = storage
      end

      # Override name to return simple "MemoryGrep"
      def name
        "MemoryGrep"
      end

      # Execute the tool
      #
      # @param pattern [String] Regex pattern to search for
      # @param case_insensitive [Boolean] Whether to perform case-insensitive search
      # @param output_mode [String] Output mode
      # @return [String] Formatted search results
      def execute(pattern:, case_insensitive: false, output_mode: "files_with_matches")
        results = @storage.grep(
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
        result << "Memory entries matching '#{pattern}' (#{paths.size} #{paths.size == 1 ? "entry" : "entries"}):"
        paths.each do |path|
          result << "  memory://#{path}"
        end
        result.join("\n")
      end

      def format_content(results, pattern)
        if results.empty?
          return "No matches found for pattern '#{pattern}'"
        end

        total_matches = results.sum { |r| r[:matches].size }
        output = []
        output << "Memory entries matching '#{pattern}' (#{results.size} #{results.size == 1 ? "entry" : "entries"}, #{total_matches} #{total_matches == 1 ? "match" : "matches"}):"
        output << ""

        results.each do |result|
          output << "memory://#{result[:path]}:"
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
        output << "Memory entries matching '#{pattern}' (#{results.size} #{results.size == 1 ? "entry" : "entries"}, #{total_matches} total #{total_matches == 1 ? "match" : "matches"}):"

        results.each do |result|
          output << "  memory://#{result[:path]}: #{result[:count]} #{result[:count] == 1 ? "match" : "matches"}"
        end

        output.join("\n")
      end
    end
  end
end
