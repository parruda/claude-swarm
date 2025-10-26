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
      DEFAULT_MODEL = "sentence-transformers/multi-qa-MiniLM-L6-cos-v1"
      EMBEDDING_DIMENSIONS = 384

      # Initialize embedder with model configuration
      #
      # Model can be configured via SWARM_MEMORY_EMBEDDING_MODEL environment variable.
      #
      # Available models:
      # - sentence-transformers/all-MiniLM-L6-v2 (default, general purpose, 256 tokens)
      # - sentence-transformers/multi-qa-MiniLM-L6-cos-v1 (Q&A optimized, 512 tokens)
      #
      # @param model [String, nil] HuggingFace model identifier (defaults to env var or DEFAULT_MODEL)
      # @param quantized [Boolean] Use quantized variant (default: false for original model)
      # @param cache_dir [String, nil] Optional custom cache directory
      # @raise [EmbeddingError] If Informers gem is not available
      #
      # Note: The original sentence-transformers model uses unquantized ONNX (90MB).
      # For a smaller quantized version (22MB), use model: "Xenova/all-MiniLM-L6-v2", quantized: true
      def initialize(model: nil, quantized: false, cache_dir: nil)
        super()

        unless defined?(Informers)
          raise EmbeddingError,
            "Informers gem is not available. Install with: gem install informers"
        end

        # Use env var if available, otherwise use provided model or default
        @model_name = model || ENV["SWARM_MEMORY_EMBEDDING_MODEL"] || DEFAULT_MODEL
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

        # Different models have different file names
        # Original sentence-transformers: model.onnx (unquantized)
        # Xenova version: model_quantized.onnx (quantized)
        suffix = @quantized ? "_quantized" : ""

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
