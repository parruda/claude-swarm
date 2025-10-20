# frozen_string_literal: true

module SwarmMemory
  module Core
    # High-level storage orchestration
    #
    # Coordinates adapter operations, path normalization, embedding generation,
    # and metadata extraction.
    #
    # @example
    #   adapter = Adapters::FilesystemAdapter.new(persist_to: ".swarm/memory.json")
    #   storage = Storage.new(adapter: adapter)
    #   storage.write(file_path: "concepts/ruby", content: "...", title: "Ruby Classes")
    class Storage
      attr_reader :adapter

      # Initialize storage with an adapter
      #
      # @param adapter [Adapters::Base] Storage adapter
      # @param embedder [Embeddings::Embedder, nil] Optional embedder for semantic search
      def initialize(adapter:, embedder: nil)
        raise ArgumentError, "adapter is required" unless adapter.is_a?(Adapters::Base)

        @adapter = adapter
        @embedder = embedder
      end

      # Write content to storage
      #
      # @param file_path [String] Path to store content
      # @param content [String] Content to store
      # @param title [String] Brief title
      # @param generate_embedding [Boolean] Whether to generate embedding (default: true if embedder present)
      # @return [Entry] The created entry
      def write(file_path:, content:, title:, generate_embedding: nil)
        # Normalize path
        normalized_path = PathNormalizer.normalize(file_path)

        # Extract metadata from frontmatter
        metadata = MetadataExtractor.extract(content)

        # Generate embedding if requested and embedder available
        embedding = nil
        should_embed = generate_embedding.nil? ? !@embedder.nil? : generate_embedding

        if should_embed && @embedder
          begin
            embedding = @embedder.embed(content)
          rescue StandardError => e
            # Don't fail write if embedding generation fails
            warn("Warning: Failed to generate embedding for #{normalized_path}: #{e.message}")
            embedding = nil
          end
        end

        # Write to adapter
        @adapter.write(
          file_path: normalized_path,
          content: content,
          title: title,
          embedding: embedding,
          metadata: metadata,
        )
      end

      # Read content from storage
      #
      # @param file_path [String] Path to read from
      # @return [String] Content at the path
      def read(file_path:)
        normalized_path = PathNormalizer.normalize(file_path)
        @adapter.read(file_path: normalized_path)
      end

      # Read full entry with metadata
      #
      # @param file_path [String] Path to read from
      # @return [Entry] Full entry object
      def read_entry(file_path:)
        normalized_path = PathNormalizer.normalize(file_path)
        @adapter.read_entry(file_path: normalized_path)
      end

      # Delete an entry
      #
      # @param file_path [String] Path to delete
      # @return [void]
      def delete(file_path:)
        normalized_path = PathNormalizer.normalize(file_path)
        @adapter.delete(file_path: normalized_path)
      end

      # List all entries
      #
      # @param prefix [String, nil] Optional prefix filter
      # @return [Array<Hash>] Entry metadata
      def list(prefix: nil)
        @adapter.list(prefix: prefix)
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
      # @return [Array<Hash>] Search results
      def grep(pattern:, case_insensitive: false, output_mode: "files_with_matches")
        @adapter.grep(
          pattern: pattern,
          case_insensitive: case_insensitive,
          output_mode: output_mode,
        )
      end

      # Clear all entries
      #
      # @return [void]
      def clear
        @adapter.clear
      end

      # Get total storage size
      #
      # @return [Integer] Size in bytes
      def total_size
        @adapter.total_size
      end

      # Get number of entries
      #
      # @return [Integer] Entry count
      def size
        @adapter.size
      end

      # Get all entries (for optimization/analysis)
      #
      # @return [Hash<String, Entry>] All entries
      def all_entries
        @adapter.all_entries
      end
    end
  end
end
