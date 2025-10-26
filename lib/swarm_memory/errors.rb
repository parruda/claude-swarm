# frozen_string_literal: true

module SwarmMemory
  # Base error class for SwarmMemory
  class Error < StandardError; end

  # Configuration errors
  class ConfigurationError < Error; end

  # Storage operation errors
  class StorageError < Error; end

  # Adapter-specific errors
  class AdapterError < Error; end

  # Search operation errors
  class SearchError < Error; end

  # Embedding generation errors
  class EmbeddingError < Error; end
end
