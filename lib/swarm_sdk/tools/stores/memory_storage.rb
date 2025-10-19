# frozen_string_literal: true

module SwarmSDK
  module Tools
    module Stores
      # MemoryStorage provides persistent, per-agent storage
      #
      # Features:
      # - Per-agent: Each agent has its own isolated storage
      # - Persistent: ALWAYS saves to JSON file
      # - Path-based: Hierarchical organization using file-path-like addresses
      # - Metadata-rich: Stores content + title + timestamp + size
      # - Thread-safe: Mutex-protected operations
      class MemoryStorage < Storage
        # Initialize memory storage with required persistence
        #
        # @param persist_to [String] Path to JSON file for persistence (REQUIRED)
        # @raise [ArgumentError] If persist_to is not provided
        def initialize(persist_to:)
          super() # Initialize parent Storage class
          raise ArgumentError, "persist_to is required for MemoryStorage" if persist_to.nil? || persist_to.to_s.strip.empty?

          @entries = {}
          @total_size = 0
          @persist_to = persist_to
          @mutex = Mutex.new

          # Load existing data if file exists
          load_from_file if File.exist?(@persist_to)
        end

        # Write content to memory storage
        #
        # @param file_path [String] Path to store content
        # @param content [String] Content to store
        # @param title [String] Brief title describing the content
        # @raise [ArgumentError] If size limits are exceeded
        # @return [Entry] The created entry
        def write(file_path:, content:, title:)
          @mutex.synchronize do
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
              raise ArgumentError, "Memory storage full (#{format_bytes(MAX_TOTAL_SIZE)} limit). " \
                "Current: #{format_bytes(@total_size)}, " \
                "Would be: #{format_bytes(new_total_size)}. " \
                "Clear old entries or use smaller content."
            end

            # Create entry
            entry = Entry.new(
              content: content,
              title: title,
              updated_at: Time.now,
              size: content_size,
            )

            # Update storage
            @entries[file_path] = entry
            @total_size = new_total_size

            # Always persist to file
            save_to_file

            entry
          end
        end

        # Read content from memory storage
        #
        # @param file_path [String] Path to read from
        # @raise [ArgumentError] If path not found
        # @return [String] Content at the path
        def read(file_path:)
          raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?

          entry = @entries[file_path]
          raise ArgumentError, "memory://#{file_path} not found" unless entry

          entry.content
        end

        # Delete a specific entry
        #
        # @param file_path [String] Path to delete
        # @raise [ArgumentError] If path not found
        # @return [void]
        def delete(file_path:)
          @mutex.synchronize do
            raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?

            entry = @entries[file_path]
            raise ArgumentError, "memory://#{file_path} not found" unless entry

            # Update total size
            @total_size -= entry.size

            # Remove entry
            @entries.delete(file_path)

            # Always persist to file
            save_to_file
          end
        end

        # List memory storage entries, optionally filtered by prefix
        #
        # @param prefix [String, nil] Filter by path prefix
        # @return [Array<Hash>] Array of entry metadata (path, title, size, updated_at)
        def list(prefix: nil)
          entries = @entries

          # Filter by prefix if provided
          if prefix && !prefix.empty?
            entries = entries.select { |path, _| path.start_with?(prefix) }
          end

          # Return metadata sorted by path
          entries.map do |path, entry|
            {
              path: path,
              title: entry.title,
              size: entry.size,
              updated_at: entry.updated_at,
            }
          end.sort_by { |e| e[:path] }
        end

        # Search entries by glob pattern
        #
        # @param pattern [String] Glob pattern (e.g., "**/*.txt", "parallel/*/task_*")
        # @return [Array<Hash>] Array of matching entry metadata, sorted by most recent first
        def glob(pattern:)
          raise ArgumentError, "pattern is required" if pattern.nil? || pattern.to_s.strip.empty?

          # Convert glob pattern to regex
          regex = glob_to_regex(pattern)

          # Filter entries by pattern
          matching_entries = @entries.select { |path, _| regex.match?(path) }

          # Return metadata sorted by most recent first
          matching_entries.map do |path, entry|
            {
              path: path,
              title: entry.title,
              size: entry.size,
              updated_at: entry.updated_at,
            }
          end.sort_by { |e| -e[:updated_at].to_f }
        end

        # Search entry content by pattern
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
            # Return paths with matching lines, sorted by most recent first
            results = []
            @entries.each do |path, entry|
              matching_lines = []
              entry.content.each_line.with_index(1) do |line, line_num|
                matching_lines << { line_number: line_num, content: line.chomp } if regex.match?(line)
              end
              results << { path: path, matches: matching_lines, updated_at: entry.updated_at } unless matching_lines.empty?
            end
            results.sort_by { |r| -r[:updated_at].to_f }.map { |r| r.except(:updated_at) }
          when "count"
            # Return paths with match counts, sorted by most recent first
            results = []
            @entries.each do |path, entry|
              count = entry.content.scan(regex).size
              results << { path: path, count: count, updated_at: entry.updated_at } if count > 0
            end
            results.sort_by { |r| -r[:updated_at].to_f }.map { |r| r.except(:updated_at) }
          else
            raise ArgumentError, "Invalid output_mode: #{output_mode}. Must be 'files_with_matches', 'content', or 'count'"
          end
        end

        # Clear all entries
        #
        # @return [void]
        def clear
          @mutex.synchronize do
            @entries.clear
            @total_size = 0
            save_to_file
          end
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

        # Save memory storage data to JSON file
        #
        # @return [void]
        def save_to_file
          # Convert entries to serializable format
          data = {
            version: 1,
            total_size: @total_size,
            entries: @entries.transform_values do |entry|
              {
                content: entry.content,
                title: entry.title,
                updated_at: entry.updated_at.iso8601,
                size: entry.size,
              }
            end,
          }

          # Ensure directory exists
          dir = File.dirname(@persist_to)
          FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

          # Write to file atomically (write to temp file, then rename)
          temp_file = "#{@persist_to}.tmp"
          File.write(temp_file, JSON.pretty_generate(data))
          File.rename(temp_file, @persist_to)
        end

        # Load memory storage data from JSON file
        #
        # @return [void]
        def load_from_file
          return unless File.exist?(@persist_to)

          data = JSON.parse(File.read(@persist_to))

          # Restore entries
          @entries = data["entries"].transform_values do |entry_data|
            Entry.new(
              content: entry_data["content"],
              title: entry_data["title"],
              updated_at: Time.parse(entry_data["updated_at"]),
              size: entry_data["size"],
            )
          end

          # Restore total size
          @total_size = data["total_size"]
        rescue JSON::ParserError => e
          # If file is corrupted, log warning and start fresh
          warn("Warning: Failed to load memory storage from #{@persist_to}: #{e.message}. Starting with empty storage.")
          @entries = {}
          @total_size = 0
        rescue StandardError => e
          # If any other error occurs, log warning and start fresh
          warn("Warning: Failed to load memory storage from #{@persist_to}: #{e.message}. Starting with empty storage.")
          @entries = {}
          @total_size = 0
        end
      end
    end
  end
end
