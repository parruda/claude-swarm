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
