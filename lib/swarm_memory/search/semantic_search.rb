# frozen_string_literal: true

module SwarmMemory
  module Search
    # Semantic search using embedding similarity
    #
    # Finds entries similar to a query based on embedding vectors
    # rather than exact text matching.
    class SemanticSearch
      # Initialize semantic search
      #
      # @param adapter [Adapters::Base] Storage adapter
      # @param embedder [Embeddings::Embedder] Embedder for generating query vectors
      def initialize(adapter:, embedder:)
        @adapter = adapter
        @embedder = embedder
      end

      # Search for entries similar to query
      #
      # @param query [String] Search query
      # @param top_k [Integer] Number of results to return
      # @param threshold [Float] Minimum similarity threshold (0.0-1.0)
      # @return [Array<Hash>] Ranked results with similarity scores
      #
      # @example
      #   results = search.find_similar(
      #     query: "How do I test Ruby code?",
      #     top_k: 5,
      #     threshold: 0.7
      #   )
      #   # => [
      #   #   { path: "skills/testing/minitest", similarity: 0.92, title: "..." },
      #   #   { path: "concepts/ruby/testing", similarity: 0.85, title: "..." }
      #   # ]
      def find_similar(query:, top_k: 5, threshold: 0.7)
        raise ArgumentError, "query is required" if query.nil? || query.to_s.strip.empty?

        # Generate query embedding
        query_embedding = @embedder.embed(query)

        # Get all entries with embeddings
        all_entries = @adapter.all_entries
        entries_with_embeddings = all_entries.select { |_, entry| entry.embedded? }

        return [] if entries_with_embeddings.empty?

        # Calculate similarities
        similarities = entries_with_embeddings.map do |path, entry|
          similarity = TextSimilarity.cosine(query_embedding, entry.embedding)

          {
            path: path,
            title: entry.title,
            similarity: similarity,
            updated_at: entry.updated_at,
          }
        end

        # Filter by threshold and sort by similarity (descending)
        results = similarities
          .select { |r| r[:similarity] >= threshold }
          .sort_by { |r| -r[:similarity] }
          .take(top_k)

        results
      end

      # Find entries similar to a given entry
      #
      # @param file_path [String] Path to reference entry
      # @param top_k [Integer] Number of results to return
      # @param threshold [Float] Minimum similarity threshold
      # @return [Array<Hash>] Ranked results (excluding the reference entry)
      def find_similar_to_entry(file_path:, top_k: 5, threshold: 0.7)
        # Get reference entry
        reference_entry = @adapter.read_entry(file_path: file_path)

        unless reference_entry.embedded?
          raise SearchError, "Entry #{file_path} has no embedding. Cannot perform semantic search."
        end

        # Get all entries with embeddings (excluding reference)
        all_entries = @adapter.all_entries
        entries_with_embeddings = all_entries
          .select { |path, entry| path != file_path && entry.embedded? }

        return [] if entries_with_embeddings.empty?

        # Calculate similarities
        similarities = entries_with_embeddings.map do |path, entry|
          similarity = TextSimilarity.cosine(reference_entry.embedding, entry.embedding)

          {
            path: path,
            title: entry.title,
            similarity: similarity,
            updated_at: entry.updated_at,
          }
        end

        # Filter by threshold and sort by similarity (descending)
        results = similarities
          .select { |r| r[:similarity] >= threshold }
          .sort_by { |r| -r[:similarity] }
          .take(top_k)

        results
      end
    end
  end
end
