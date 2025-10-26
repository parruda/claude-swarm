# frozen_string_literal: true

module SwarmMemory
  module Search
    # Text similarity calculations using multiple algorithms
    #
    # Provides both Jaccard (word overlap) and cosine similarity metrics.
    class TextSimilarity
      class << self
        # Calculate Jaccard similarity between two texts
        #
        # Jaccard similarity measures the overlap of word sets.
        # Score ranges from 0.0 (no overlap) to 1.0 (identical).
        #
        # @param text1 [String] First text
        # @param text2 [String] Second text
        # @return [Float] Similarity score 0.0-1.0
        #
        # @example
        #   TextSimilarity.jaccard("ruby classes", "ruby modules")
        #   # => 0.33 (1 shared word out of 3 total unique words)
        def jaccard(text1, text2)
          words1 = tokenize(text1)
          words2 = tokenize(text2)

          return 0.0 if words1.empty? && words2.empty?
          return 0.0 if words1.empty? || words2.empty?

          intersection = (words1 & words2).size
          union = (words1 | words2).size

          return 0.0 if union.zero?

          intersection.to_f / union
        end

        # Calculate cosine similarity between two embedding vectors
        #
        # Cosine similarity measures the angle between vectors.
        # Score ranges from -1.0 to 1.0 (0.0-1.0 for normalized embeddings).
        #
        # @param vec1 [Array<Float>] First embedding vector
        # @param vec2 [Array<Float>] Second embedding vector
        # @return [Float] Similarity score -1.0 to 1.0
        #
        # @example
        #   vec1 = [0.1, 0.2, 0.3]
        #   vec2 = [0.2, 0.3, 0.4]
        #   TextSimilarity.cosine(vec1, vec2)
        #   # => 0.99 (very similar)
        def cosine(vec1, vec2)
          raise ArgumentError, "Vectors must have same length" if vec1.size != vec2.size
          return 0.0 if vec1.empty?

          dot_product = vec1.zip(vec2).sum { |a, b| a * b }
          magnitude1 = Math.sqrt(vec1.sum { |x| x * x })
          magnitude2 = Math.sqrt(vec2.sum { |x| x * x })

          return 0.0 if magnitude1.zero? || magnitude2.zero?

          dot_product / (magnitude1 * magnitude2)
        end

        private

        # Tokenize text into normalized words
        #
        # @param text [String] Text to tokenize
        # @return [Set<String>] Set of normalized words
        def tokenize(text)
          text
            .downcase
            .scan(/\w+/) # Extract words only
            .reject { |w| w.length < 3 } # Remove very short words (a, is, to, etc.)
            .to_set
        end
      end
    end
  end
end
