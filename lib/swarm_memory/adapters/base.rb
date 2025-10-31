# frozen_string_literal: true

module SwarmMemory
  module Adapters
    # Abstract base adapter interface for memory storage backends
    #
    # Subclasses must implement all public methods to provide
    # different storage backends (filesystem, Redis, SQLite, etc.)
    class Base
      # Maximum size per entry (3MB)
      MAX_ENTRY_SIZE = 3_000_000

      # Maximum total storage size (100GB)
      MAX_TOTAL_SIZE = 100_000_000_000

      # Write content to storage
      #
      # @param file_path [String] Path to store content
      # @param content [String] Content to store
      # @param title [String] Brief title describing the content
      # @param embedding [Array<Float>, nil] Optional embedding vector
      # @param metadata [Hash, nil] Optional metadata
      # @raise [ArgumentError] If size limits are exceeded
      # @return [Core::Entry] The created entry
      def write(file_path:, content:, title:, embedding: nil, metadata: nil)
        raise NotImplementedError, "Subclass must implement #write"
      end

      # Read content from storage
      #
      # @param file_path [String] Path to read from
      # @raise [ArgumentError] If path not found
      # @return [String] Content at the path
      def read(file_path:)
        raise NotImplementedError, "Subclass must implement #read"
      end

      # Read full entry with metadata
      #
      # @param file_path [String] Path to read from
      # @raise [ArgumentError] If path not found
      # @return [Core::Entry] Full entry object
      def read_entry(file_path:)
        raise NotImplementedError, "Subclass must implement #read_entry"
      end

      # Delete a specific entry
      #
      # @param file_path [String] Path to delete
      # @raise [ArgumentError] If path not found
      # @return [void]
      def delete(file_path:)
        raise NotImplementedError, "Subclass must implement #delete"
      end

      # List entries, optionally filtered by prefix
      #
      # @param prefix [String, nil] Filter by path prefix
      # @return [Array<Hash>] Array of entry metadata (path, title, size, updated_at)
      def list(prefix: nil)
        raise NotImplementedError, "Subclass must implement #list"
      end

      # Search entries by glob pattern
      #
      # @param pattern [String] Glob pattern (e.g., "**/*.txt", "parallel/*/task_*")
      # @return [Array<Hash>] Array of matching entry metadata, sorted by most recent first
      def glob(pattern:)
        raise NotImplementedError, "Subclass must implement #glob"
      end

      # Search entry content by pattern
      #
      # @param pattern [String] Regular expression pattern to search for
      # @param case_insensitive [Boolean] Whether to perform case-insensitive search
      # @param output_mode [String] Output mode: "files_with_matches" (default), "content", or "count"
      # @param path [String, nil] Optional path prefix filter (e.g., "concept/", "fact/api-design")
      # @return [Array<Hash>, String] Results based on output_mode
      def grep(pattern:, case_insensitive: false, output_mode: "files_with_matches", path: nil)
        raise NotImplementedError, "Subclass must implement #grep"
      end

      # Clear all entries
      #
      # @return [void]
      def clear
        raise NotImplementedError, "Subclass must implement #clear"
      end

      # Get current total size
      #
      # @return [Integer] Total size in bytes
      def total_size
        raise NotImplementedError, "Subclass must implement #total_size"
      end

      # Get number of entries
      #
      # @return [Integer] Number of entries
      def size
        raise NotImplementedError, "Subclass must implement #size"
      end

      protected

      # Format bytes to human-readable size
      #
      # @param bytes [Integer] Number of bytes
      # @return [String] Formatted size (e.g., "1.5MB", "500.0KB")
      def format_bytes(bytes)
        if bytes >= 1_000_000
          "#{(bytes.to_f / 1_000_000).round(1)}MB"
        elsif bytes >= 1_000
          "#{(bytes.to_f / 1_000).round(1)}KB"
        else
          "#{bytes}B"
        end
      end

      # Convert glob pattern to regex
      #
      # @param pattern [String] Glob pattern
      # @return [Regexp] Regular expression
      def glob_to_regex(pattern)
        # Escape special regex characters except glob wildcards
        escaped = Regexp.escape(pattern)

        # Convert glob wildcards to regex
        # ** matches any number of directories (including zero)
        escaped = escaped.gsub('\*\*', ".*")
        # * matches anything except directory separator
        escaped = escaped.gsub('\*', "[^/]*")
        # ? matches single character except directory separator
        escaped = escaped.gsub('\?', "[^/]")

        # Anchor to start and end
        Regexp.new("\\A#{escaped}\\z")
      end
    end
  end
end
