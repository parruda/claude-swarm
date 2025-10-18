# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Stores
      # Scratchpad provides session-scoped, in-memory storage for agents
      # to store detailed outputs that would otherwise bloat tool responses.
      #
      # Features:
      # - Session-scoped: Cleared when swarm execution completes
      # - Shared: Any agent can read/write any scratchpad address
      # - Path-based: Hierarchical organization using file-path-like addresses
      # - In-memory: No filesystem I/O, pure memory storage
      # - Metadata-rich: Stores content + title + timestamp + size
      class Scratchpad
        # Maximum size per scratchpad entry (1MB)
        MAX_ENTRY_SIZE = 1_000_000

        # Maximum total scratchpad size (100MB)
        MAX_TOTAL_SIZE = 100_000_000

        # Represents a single scratchpad entry with metadata
        Entry = Struct.new(:content, :title, :created_at, :size, keyword_init: true)

        def initialize
          @entries = {}
          @total_size = 0
        end

        # Write content to scratchpad
        #
        # @param file_path [String] Path to store content
        # @param content [String] Content to store
        # @param title [String] Brief title describing the content
        # @raise [ArgumentError] If size limits are exceeded
        # @return [Entry] The created entry
        def write(file_path:, content:, title:)
          raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?
          raise ArgumentError, "content is required" if content.nil?
          raise ArgumentError, "title is required" if title.nil? || title.to_s.strip.empty?

          content_size = content.bytesize

          # Check entry size limit
          if content_size > MAX_ENTRY_SIZE
            raise ArgumentError, "Content exceeds maximum size (#{format_bytes(MAX_ENTRY_SIZE)}). " \
              "Current: #{format_bytes(content_size)}"
          end

          # Calculate new total size
          existing_entry = @entries[file_path]
          existing_size = existing_entry ? existing_entry.size : 0
          new_total_size = @total_size - existing_size + content_size

          # Check total size limit
          if new_total_size > MAX_TOTAL_SIZE
            raise ArgumentError, "Scratchpad full (#{format_bytes(MAX_TOTAL_SIZE)} limit). " \
              "Current: #{format_bytes(@total_size)}, " \
              "Would be: #{format_bytes(new_total_size)}. " \
              "Clear old entries or use smaller content."
          end

          # Create entry
          entry = Entry.new(
            content: content,
            title: title,
            created_at: Time.now,
            size: content_size,
          )

          # Update storage
          @entries[file_path] = entry
          @total_size = new_total_size

          entry
        end

        # Read content from scratchpad
        #
        # @param file_path [String] Path to read from
        # @raise [ArgumentError] If path not found
        # @return [String] Content at the path
        def read(file_path:)
          raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?

          entry = @entries[file_path]
          raise ArgumentError, "scratchpad://#{file_path} not found" unless entry

          entry.content
        end

        # List scratchpad entries, optionally filtered by prefix
        #
        # @param prefix [String, nil] Filter by path prefix
        # @return [Array<Hash>] Array of entry metadata (path, title, size, created_at)
        def list(prefix: nil)
          entries = @entries

          # Filter by prefix if provided
          if prefix && !prefix.empty?
            entries = entries.select { |path, _| path.start_with?(prefix) }
          end

          # Return metadata
          entries.map do |path, entry|
            {
              path: path,
              title: entry.title,
              size: entry.size,
              created_at: entry.created_at,
            }
          end.sort_by { |e| e[:path] }
        end

        # Search entries by glob pattern (like filesystem glob)
        #
        # @param pattern [String] Glob pattern (e.g., "**/*.txt", "parallel/*/task_*")
        # @return [Array<Hash>] Array of matching entry metadata (path, title, size, created_at)
        def glob(pattern:)
          raise ArgumentError, "pattern is required" if pattern.nil? || pattern.to_s.strip.empty?

          # Convert glob pattern to regex
          regex = glob_to_regex(pattern)

          # Filter entries by pattern
          matching_entries = @entries.select { |path, _| regex.match?(path) }

          # Return metadata sorted by path
          matching_entries.map do |path, entry|
            {
              path: path,
              title: entry.title,
              size: entry.size,
              created_at: entry.created_at,
            }
          end.sort_by { |e| e[:path] }
        end

        # Search entry content by pattern (like grep)
        #
        # @param pattern [String] Regular expression pattern to search for
        # @param case_insensitive [Boolean] Whether to perform case-insensitive search
        # @param output_mode [String] Output mode: "files_with_matches" (default), "content", or "count"
        # @return [Array<Hash>, String] Results based on output_mode
        def grep(pattern:, case_insensitive: false, output_mode: "files_with_matches")
          raise ArgumentError, "pattern is required" if pattern.nil? || pattern.to_s.strip.empty?

          # Create regex from pattern
          flags = case_insensitive ? Regexp::IGNORECASE : 0
          regex = Regexp.new(pattern, flags)

          case output_mode
          when "files_with_matches"
            # Return just the paths that match
            matching_paths = @entries.select { |_path, entry| regex.match?(entry.content) }
              .map { |path, _| path }
              .sort
            matching_paths
          when "content"
            # Return paths with matching lines
            results = []
            @entries.each do |path, entry|
              matching_lines = []
              entry.content.each_line.with_index(1) do |line, line_num|
                matching_lines << { line_number: line_num, content: line.chomp } if regex.match?(line)
              end
              results << { path: path, matches: matching_lines } unless matching_lines.empty?
            end
            results.sort_by { |r| r[:path] }
          when "count"
            # Return paths with match counts
            results = []
            @entries.each do |path, entry|
              count = entry.content.scan(regex).size
              results << { path: path, count: count } if count > 0
            end
            results.sort_by { |r| r[:path] }
          else
            raise ArgumentError, "Invalid output_mode: #{output_mode}. Must be 'files_with_matches', 'content', or 'count'"
          end
        end

        # Clear all entries
        #
        # @return [void]
        def clear
          @entries.clear
          @total_size = 0
        end

        # Get current total size
        #
        # @return [Integer] Total size in bytes
        attr_reader :total_size

        # Get number of entries
        #
        # @return [Integer] Number of entries
        def size
          @entries.size
        end

        private

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
      end
    end
  end
end
