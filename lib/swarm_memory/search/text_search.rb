# frozen_string_literal: true

module SwarmMemory
  module Search
    # Text-based search operations (glob and grep)
    #
    # Provides a clean API for text-based search that wraps adapter operations.
    # This layer could add additional logic like query parsing, ranking, etc.
    class TextSearch
      # Initialize text search
      #
      # @param adapter [Adapters::Base] Storage adapter
      def initialize(adapter:)
        @adapter = adapter
      end

      # Search by glob pattern
      #
      # @param pattern [String] Glob pattern
      # @return [Array<Hash>] Matching entries
      def glob(pattern:)
        @adapter.glob(pattern: pattern)
      end

      # Search by content pattern
      #
      # @param pattern [String] Regex pattern
      # @param case_insensitive [Boolean] Case-insensitive search
      # @param output_mode [String] Output mode
      # @param path [String, nil] Optional path prefix filter
      # @return [Array<Hash>] Search results
      def grep(pattern:, case_insensitive: false, output_mode: "files_with_matches", path: nil)
        @adapter.grep(
          pattern: pattern,
          case_insensitive: case_insensitive,
          output_mode: output_mode,
          path: path,
        )
      end
    end
  end
end
