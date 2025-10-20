# frozen_string_literal: true

module SwarmMemory
  module Embeddings
    # Abstract embedder interface
    #
    # Subclasses implement different embedding providers
    # (Informers, OpenAI API, etc.)
    class Embedder
      # Generate embedding for single text
      #
      # @param text [String] Text to embed
      # @return [Array<Float>] Embedding vector
      # @raise [EmbeddingError] If embedding generation fails
      def embed(text)
        raise NotImplementedError, "Subclass must implement #embed"
      end

      # Generate embeddings for multiple texts (batched)
      #
      # @param texts [Array<String>] Texts to embed
      # @return [Array<Array<Float>>] Array of embedding vectors
      # @raise [EmbeddingError] If embedding generation fails
      def embed_batch(texts)
        raise NotImplementedError, "Subclass must implement #embed_batch"
      end

      # Get embedding dimensionality
      #
      # @return [Integer] Vector dimensions
      def dimensions
        raise NotImplementedError, "Subclass must implement #dimensions"
      end
    end
  end
end
