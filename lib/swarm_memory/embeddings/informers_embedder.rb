# frozen_string_literal: true

module SwarmMemory
  module Embeddings
    # Embedder implementation using Informers gem (fast ONNX inference)
    #
    # Uses sentence-transformers models via ONNX for fast, local embedding generation.
    # Supports quantized models for even better performance.
    #
    # @example
    #   embedder = InformersEmbedder.new
    #   vector = embedder.embed("This is a test sentence")
    #   vector.size # => 384
    class InformersEmbedder < Embedder
      DEFAULT_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
      EMBEDDING_DIMENSIONS = 384

      # Initialize embedder with model configuration
      #
      # @param model [String] HuggingFace model identifier
      # @param quantized [Boolean] Use quantized variant for speed (default: true)
      # @param cache_dir [String, nil] Optional custom cache directory
      # @raise [EmbeddingError] If Informers gem is not available
      def initialize(model: DEFAULT_MODEL, quantized: true, cache_dir: nil)
        super()

        unless defined?(Informers)
          raise EmbeddingError,
            "Informers gem is not available. Install with: gem install informers"
        end

        @model_name = model
        @quantized = quantized
        @model = nil # Lazy load

        # Optional: Set custom cache directory
        Informers.cache_dir = cache_dir if cache_dir
      end

      # Explicitly pre-load the model (triggers download if not cached)
      #
      # Call this during initialization to download the model immediately
      # rather than waiting for the first embedding call.
      #
      # @return [self]
      #
      # @example
      #   embedder = InformersEmbedder.new
      #   embedder.preload!  # Downloads ~80MB model on first call
      #   embedder.embed("text")  # No download wait
      def preload!
        ensure_model_loaded
        self
      end

      # Check if model is already cached locally
      #
      # @return [Boolean] True if model files exist in cache
      #
      # @example
      #   embedder = InformersEmbedder.new
      #   if embedder.cached?
      #     puts "Ready to use!"
      #   else
      #     puts "Will download on first use (~80MB)"
      #   end
      def cached?
        cache_dir = Informers.cache_dir
        dtype = @quantized ? "q8" : "fp32"
        suffix = dtype == "q8" ? "_quantized" : ""

        # Check for required model files
        model_file = File.join(cache_dir, @model_name, "onnx", "model#{suffix}.onnx")
        tokenizer_file = File.join(cache_dir, @model_name, "tokenizer.json")

        File.exist?(model_file) && File.exist?(tokenizer_file)
      end

      # Generate embedding for single text
      #
      # @param text [String] Text to embed
      # @return [Array<Float>] 384-dimensional embedding vector
      # @raise [EmbeddingError] If embedding generation fails
      def embed(text)
        raise ArgumentError, "text is required" if text.nil? || text.to_s.strip.empty?

        begin
          ensure_model_loaded
          # Informers handles single strings directly - returns single embedding array
          @model.call(text)
        rescue StandardError => e
          raise EmbeddingError, "Failed to generate embedding: #{e.message}"
        end
      end

      # Generate embeddings for multiple texts (batched)
      #
      # @param texts [Array<String>] Texts to embed
      # @return [Array<Array<Float>>] Array of embedding vectors
      # @raise [EmbeddingError] If embedding generation fails
      def embed_batch(texts)
        raise ArgumentError, "texts must be an array" unless texts.is_a?(Array)
        raise ArgumentError, "texts cannot be empty" if texts.empty?

        begin
          ensure_model_loaded
          # Batch call - returns array of embedding arrays
          @model.call(texts)
        rescue StandardError => e
          raise EmbeddingError, "Failed to generate embeddings: #{e.message}"
        end
      end

      # Get embedding dimensionality
      #
      # @return [Integer] Vector dimensions (384 for all-MiniLM-L6-v2)
      def dimensions
        EMBEDDING_DIMENSIONS
      end

      private

      # Lazy load the Informers model
      #
      # @return [void]
      def ensure_model_loaded
        return if @model

        @model = Informers.pipeline(
          "embedding",
          @model_name,
          quantized: @quantized,
        )
      rescue StandardError => e
        raise EmbeddingError, "Failed to load embedding model '#{@model_name}': #{e.message}"
      end
    end
  end
end
