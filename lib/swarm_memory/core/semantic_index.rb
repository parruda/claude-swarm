# frozen_string_literal: true

module SwarmMemory
  module Core
    # Semantic search abstraction layer
    #
    # Provides embedding computation and semantic search operations
    # that work with any storage adapter. Easily replaceable with
    # vector database implementations (Qdrant, Milvus, Chroma, etc.)
    #
    # Uses hybrid search: combines semantic similarity with keyword matching
    # for better recall accuracy.
    #
    # @example
    #   index = SemanticIndex.new(adapter: adapter, embedder: embedder)
    #   results = index.search(query: "how to debug", top_k: 5, threshold: 0.7)
    class SemanticIndex
      # Default weights for hybrid scoring
      DEFAULT_SEMANTIC_WEIGHT = 0.5
      DEFAULT_KEYWORD_WEIGHT = 0.5

      # @param adapter [Adapters::Base] Storage adapter
      # @param embedder [Embeddings::Embedder] Embedding model
      # @param semantic_weight [Float] Weight for semantic similarity (0.0-1.0)
      # @param keyword_weight [Float] Weight for keyword matching (0.0-1.0)
      def initialize(adapter:, embedder:, semantic_weight: DEFAULT_SEMANTIC_WEIGHT, keyword_weight: DEFAULT_KEYWORD_WEIGHT)
        @adapter = adapter
        @embedder = embedder
        @semantic_weight = semantic_weight
        @keyword_weight = keyword_weight
      end

      # Compute embedding for text
      #
      # @param text [String] Text to embed
      # @return [Array<Float>] Embedding vector
      def compute_embedding(text)
        @embedder.embed(text)
      end

      # Semantic search by text query
      #
      # @param query [String] Search query
      # @param top_k [Integer] Number of results to return
      # @param threshold [Float] Minimum similarity score (0.0-1.0)
      # @param filter [Hash, nil] Optional metadata filters (e.g., { "type" => "skill" })
      # @return [Array<Hash>] Results with similarity scores, sorted by similarity descending
      #
      # @example
      #   results = index.search(
      #     query: "how to create a swarm",
      #     top_k: 3,
      #     threshold: 0.65,
      #     filter: { "type" => "skill" }
      #   )
      #
      #   results.each do |result|
      #     puts "#{result[:path]} (#{result[:similarity]})"
      #     puts result[:title]
      #   end
      def search(query:, top_k: 10, threshold: 0.0, filter: nil)
        # Extract keywords from query for keyword matching
        query_keywords = extract_keywords(query)

        # Compute query embedding
        query_embedding = compute_embedding(query)

        # Delegate to adapter-specific search (gets semantic similarity only)
        # Use threshold of 0.0 to get all results, we'll filter after hybrid scoring
        results = @adapter.semantic_search(
          embedding: query_embedding,
          top_k: top_k * 3, # Get extra for reranking
          threshold: 0.0,   # No threshold yet - will apply after hybrid scoring
        )

        # Calculate hybrid scores (semantic + keyword)
        results = calculate_hybrid_scores(results, query_keywords)

        # Apply metadata filters if provided
        results = apply_filters(results, filter) if filter

        # Filter by threshold on hybrid score
        results = results.select { |r| r[:similarity] >= threshold }

        # Return top K after filtering and reranking
        results.take(top_k)
      end

      # Find similar entries by embedding vector
      #
      # @param embedding [Array<Float>] Embedding vector
      # @param top_k [Integer] Number of results to return
      # @param threshold [Float] Minimum similarity score (0.0-1.0)
      # @param filter [Hash, nil] Optional metadata filters
      # @return [Array<Hash>] Similar entries sorted by similarity descending
      def find_similar(embedding:, top_k: 10, threshold: 0.0, filter: nil)
        results = @adapter.semantic_search(
          embedding: embedding,
          top_k: top_k * 2,
          threshold: threshold,
        )

        # Apply metadata filters if provided
        results = apply_filters(results, filter) if filter

        # Return top K after filtering
        results.take(top_k)
      end

      private

      # Extract keywords from query text
      #
      # Removes common words and punctuation, lowercases everything.
      #
      # @param text [String] Query text
      # @return [Array<String>] Extracted keywords
      def extract_keywords(text)
        # Common stop words to ignore
        stop_words = [
          "a",
          "an",
          "and",
          "are",
          "as",
          "at",
          "be",
          "by",
          "for",
          "from",
          "has",
          "have",
          "in",
          "is",
          "it",
          "of",
          "on",
          "that",
          "the",
          "this",
          "to",
          "was",
          "will",
          "with",
          "how",
          "what",
          "when",
          "where",
          "why",
          "who",
          "which",
          "do",
          "does",
          "did",
          "can",
          "could",
          "should",
          "would",
          "may",
          "might",
          "must",
          "me",
          "my",
          "you",
          "your",
          "we",
          "us",
          "our",
        ]

        # Extract words (lowercase, alphanumeric only)
        words = text.downcase
          .gsub(/[^a-z0-9\s\-]/, " ") # Remove punctuation except hyphens
          .split(/\s+/)
          .reject { |w| w.length < 2 } # Skip single chars
          .reject { |w| stop_words.include?(w) } # Skip stop words

        words.uniq
      end

      # Calculate hybrid scores combining semantic similarity and keyword matching
      #
      # @param results [Array<Hash>] Results with semantic :similarity scores
      # @param query_keywords [Array<String>] Keywords from query
      # @return [Array<Hash>] Results with updated :similarity (hybrid score) and debug info
      def calculate_hybrid_scores(results, query_keywords)
        results.map do |result|
          semantic_score = result[:similarity]
          keyword_score = calculate_keyword_score(result, query_keywords)

          # Hybrid score: weighted combination
          hybrid_score = (@semantic_weight * semantic_score) + (@keyword_weight * keyword_score)

          # Update result with hybrid score and debug info
          result.merge(
            similarity: hybrid_score,
            semantic_score: semantic_score,
            keyword_score: keyword_score,
          )
        end.sort_by { |r| -r[:similarity] }
      end

      # Calculate keyword matching score based on tag overlap
      #
      # @param result [Hash] Search result with :metadata containing tags
      # @param query_keywords [Array<String>] Keywords from query
      # @return [Float] Keyword score (0.0-1.0)
      def calculate_keyword_score(result, query_keywords)
        return 0.0 if query_keywords.empty?

        # Get tags from metadata
        tags = result.dig(:metadata, "tags") || result.dig(:metadata, :tags) || []
        return 0.0 if tags.empty?

        # Normalize tags to lowercase
        normalized_tags = tags.map(&:downcase)

        # Count keyword matches (fuzzy matching - substring or contains)
        matches = query_keywords.count do |keyword|
          normalized_tags.any? { |tag| tag.include?(keyword) || keyword.include?(tag) }
        end

        # Normalize to 0-1 scale
        # Use min(query_keywords.size, 5) as denominator to avoid penalizing long queries
        denominator = [query_keywords.size, 5].min
        matches.to_f / denominator
      end

      # Apply metadata filters to results
      #
      # @param results [Array<Hash>] Search results
      # @param filter [Hash] Metadata filters
      # @return [Array<Hash>] Filtered results
      def apply_filters(results, filter)
        results.select do |result|
          filter.all? do |key, value|
            result.dig(:metadata, key) == value || result.dig(:metadata, key.to_s) == value
          end
        end
      end
    end
  end
end
