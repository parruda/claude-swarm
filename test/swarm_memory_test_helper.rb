# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "webmock/minitest"

# Load swarm_memory (will load swarm_sdk and ruby_llm)
require "swarm_memory"

# Mock embedder for tests to avoid downloading models
class MockEmbedder
  def embed(text)
    # Return a simple fixed-size vector for testing
    Array.new(384) { rand }
  end

  def embed_batch(texts)
    texts.map { |_text| embed("") }
  end
end

# Monkey-patch InformersEmbedder to return mock in tests
# This prevents model downloads while keeping production code clean
module SwarmMemory
  module Embeddings
    class InformersEmbedder
      alias_method :original_initialize, :initialize

      def initialize
        # In tests, just set up a mock - don't download model
        @model = :mock
      end

      alias_method :original_embed, :embed

      def embed(text)
        # Return fixed-size vector for testing
        Array.new(384) { rand }
      end
    end
  end
end

module SwarmMemoryTestHelper
  # Create a temporary storage for testing
  #
  # @return [SwarmMemory::Core::Storage] Temporary storage instance
  def create_temp_storage
    temp_dir = File.join(Dir.tmpdir, "test-memory-#{SecureRandom.hex(8)}")
    adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: temp_dir)
    SwarmMemory::Core::Storage.new(adapter: adapter)
  end

  # Clean up temporary storage directory
  #
  # @param storage [SwarmMemory::Core::Storage] Storage to cleanup
  # @return [void]
  def cleanup_storage(storage)
    dir_path = storage.adapter.instance_variable_get(:@directory)
    FileUtils.rm_rf(dir_path) if dir_path && Dir.exist?(dir_path)
  end

  # Create sample memory entry (pure content, no frontmatter)
  #
  # Frontmatter is now passed as separate metadata params to MemoryWrite,
  # not embedded in content.
  #
  # @return [String] Content only
  def create_sample_entry
    <<~ENTRY
      # Sample Entry

      This is a sample entry for testing purposes.
    ENTRY
  end

  # Create sample metadata hash
  #
  # @param type [String] Entry type
  # @param confidence [String] Confidence level
  # @param tags [Array<String>] Tags
  # @return [Hash] Metadata hash
  def create_sample_metadata(type: "concept", confidence: "high", tags: ["test"])
    {
      "type" => type,
      "confidence" => confidence,
      "tags" => tags,
      "last_verified" => Date.today.to_s,
    }
  end
end

# Include helper in all test classes
module Minitest
  class Test
    include SwarmMemoryTestHelper
  end
end
