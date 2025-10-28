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

        # Create semantic index if embedder is provided
        @semantic_index = if embedder
          SemanticIndex.new(adapter: adapter, embedder: embedder)
        end
      end

      # Get semantic index for semantic search operations
      #
      # @return [SemanticIndex, nil] Semantic index instance or nil if no embedder
      attr_reader :semantic_index

      # Write content to storage
      #
      # @param file_path [String] Path to store content (with .md extension)
      # @param content [String] Content to store (pure markdown)
      # @param title [String] Brief title
      # @param metadata [Hash, nil] Optional metadata
      # @param generate_embedding [Boolean] Whether to generate embedding (default: true if embedder present)
      # @return [Entry] The created entry
      def write(file_path:, content:, title:, metadata: nil, generate_embedding: nil)
        # Normalize path
        normalized_path = PathNormalizer.normalize(file_path)

        # Generate embedding if requested and embedder available
        embedding = nil
        should_embed = generate_embedding.nil? ? !@embedder.nil? : generate_embedding

        if should_embed && @embedder
          begin
            # Build searchable text for better semantic matching
            # Uses title + tags + first paragraph instead of full content
            searchable_text = build_searchable_text(content, title, metadata)

            # ALWAYS emit to LogStream (create if needed for debugging)
            # This ensures we can see what's being embedded
            begin
              if defined?(SwarmSDK::LogStream)
                SwarmSDK::LogStream.emit(
                  type: "memory_embedding_generated",
                  file_path: normalized_path,
                  title: title,
                  searchable_text_length: searchable_text.length,
                  searchable_text_preview: searchable_text.slice(0, 300),
                  full_searchable_text: searchable_text,
                  metadata_tags: metadata&.dig("tags"),
                  metadata_domain: metadata&.dig("domain"),
                )
              end
            rescue StandardError => e
              # Don't fail if logging fails
              warn("Failed to log embedding: #{e.message}")
            end

            embedding = @embedder.embed(searchable_text)
          rescue StandardError => e
            # Don't fail write if embedding generation fails
            warn("Warning: Failed to generate embedding for #{normalized_path}: #{e.message}")
            embedding = nil
          end
        end

        # Write to adapter (metadata passed from tool parameters)
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

      # Read full entry with metadata, automatically following stub redirects
      #
      # @param file_path [String] Path to read from
      # @param _visited [Array<String>] Internal: tracks visited paths to detect circular redirects
      # @return [Entry] Full entry object
      # @raise [ArgumentError] If path not found, circular redirect detected, or too many redirects
      def read_entry(file_path:, _visited: [])
        normalized_path = PathNormalizer.normalize(file_path)

        # Detect circular redirects immediately
        if _visited.include?(normalized_path)
          cycle = _visited + [normalized_path]
          raise ArgumentError,
            "Circular redirect detected in memory storage: #{cycle.join(" → ")}\n\n" \
              "This indicates corrupted stub files. Please run MemoryDefrag to repair:\n  " \
              "MemoryDefrag(action: \"analyze\")"
        end

        # Check depth limit (prevent infinite chains)
        if _visited.size >= 5
          chain = _visited + [normalized_path]
          raise ArgumentError,
            "Memory redirect chain too deep (>5 redirects): #{chain.join(" → ")}\n\n" \
              "This indicates fragmented memory storage. Please run maintenance:\n  " \
              "MemoryDefrag(action: \"full\", dry_run: true)  # Preview first\n  " \
              "MemoryDefrag(action: \"full\", dry_run: false) # Execute"
        end

        # Read entry from adapter
        begin
          entry = @adapter.read_entry(file_path: normalized_path)
        rescue ArgumentError
          # If this is a redirect target that doesn't exist, provide helpful error
          if _visited.empty?
            # Not a redirect, just re-raise original error
            raise
          else
            original_path = _visited.first
            raise ArgumentError,
              "memory://#{original_path} was redirected to memory://#{normalized_path}, but the target was not found.\n\n" \
                "The original entry may have been merged or moved incorrectly. " \
                "Run MemoryDefrag to identify and fix broken redirects:\n  " \
                "MemoryDefrag(action: \"analyze\")"
          end
        end

        # Check if this is a stub redirect
        if entry.metadata && entry.metadata["stub"] == true
          redirect_target = entry.metadata["redirect_to"]

          # Validate redirect target exists
          if redirect_target.nil? || redirect_target.strip.empty?
            raise ArgumentError,
              "memory://#{normalized_path} is a stub with invalid redirect metadata.\n\n" \
                "This should never happen (stubs are created by MemoryDefrag). " \
                "The stub file may be corrupted. Please report this as a bug."
          end

          # Follow redirect recursively, tracking visited paths
          return read_entry(file_path: redirect_target, _visited: _visited + [normalized_path])
        end

        # Not a stub, return the entry
        entry
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

      private

      # Build searchable text for embedding
      #
      # Creates a condensed representation optimized for semantic search.
      # Uses title + tags + first paragraph instead of full content.
      #
      # @param content [String] Full entry content
      # @param title [String] Entry title
      # @param metadata [Hash, nil] Entry metadata
      # @return [String] Searchable text for embedding
      def build_searchable_text(content, title, metadata)
        parts = []

        # 1. Title (most important for matching)
        parts << "Title: #{title}"

        # 2. Tags (critical keywords that users would search for)
        if metadata && metadata["tags"]&.any?
          parts << "Tags: #{metadata["tags"].join(", ")}"
        end

        # 3. Domain (additional context)
        if metadata && metadata["domain"]
          parts << "Domain: #{metadata["domain"]}"
        end

        # 4. First paragraph (summary/description)
        first_para = extract_first_paragraph(content)
        parts << "Summary: #{first_para}" if first_para

        parts.join("\n\n")
      end

      # Extract first meaningful paragraph from content
      #
      # Skips YAML frontmatter, headings, and empty lines to find
      # the first substantive paragraph.
      #
      # Character limit can be controlled via SWARM_MEMORY_EMBEDDING_MAX_CHARS:
      # - Default: 300
      # - -1: Unlimited (use full content)
      # - Any positive number: Custom limit
      #
      # @param content [String] Full content
      # @return [String, nil] First paragraph (max chars based on env var) or nil
      def extract_first_paragraph(content)
        return if content.nil? || content.strip.empty?

        # Get character limit from environment variable
        # Default: 300, -1 = unlimited
        max_chars = (ENV["SWARM_MEMORY_EMBEDDING_MAX_CHARS"] || "1200").to_i
        unlimited = max_chars == -1

        lines = content.lines

        # Skip YAML frontmatter (--- ... ---)
        in_frontmatter = false
        lines = lines.drop_while do |line|
          if line.strip == "---"
            in_frontmatter = !in_frontmatter
            true
          else
            in_frontmatter
          end
        end

        # Find first non-heading, non-empty paragraph(s)
        paragraph = []
        lines.each do |line|
          stripped = line.strip

          # Skip empty lines
          next if stripped.empty?

          # Stop if we hit a heading after collecting some text (unless unlimited)
          if stripped.start_with?("#") && paragraph.any? && !unlimited
            break
          end

          # Skip headings
          next if stripped.start_with?("#")

          # Skip code blocks
          next if stripped.start_with?("```")

          # Add line to paragraph
          paragraph << stripped

          # Stop if we have enough text (unless unlimited)
          unless unlimited
            break if paragraph.join(" ").length > (max_chars - 100)
          end
        end

        return if paragraph.empty?

        # Join and cap at max_chars (or don't cap if unlimited)
        text = paragraph.join(" ")
        unlimited ? text : text.slice(0, max_chars)
      end
    end
  end
end
