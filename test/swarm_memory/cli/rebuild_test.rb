# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

# Test the rebuild functionality (core mechanism used by CLI)
#
# Note: We don't test the CLI commands directly since they call exit(),
# but we test the underlying rebuild mechanism that the CLI uses.
class RebuildTest < Minitest::Test
  def setup
    @temp_dir = File.join(Dir.tmpdir, "test-rebuild-#{SecureRandom.hex(8)}")
    @adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)

    # Create a mock embedder for testing
    @embedder = MockEmbedder.new
    @storage = SwarmMemory::Core::Storage.new(adapter: @adapter, embedder: @embedder)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  def test_rebuild_regenerates_embeddings_for_all_entries
    # Write some test entries with embeddings
    @storage.write(
      file_path: "concept/ruby/classes.md",
      content: "# Ruby Classes\n\nClasses are blueprints for objects.",
      title: "Ruby Classes",
      metadata: {
        "type" => "concept",
        "confidence" => "high",
        "tags" => ["ruby", "oop"],
        "domain" => "programming/ruby",
        "source" => "documentation",
      },
    )

    @storage.write(
      file_path: "skill/debugging/trace.md",
      content: "# Trace Errors\n\n1. Read stack trace\n2. Find root cause",
      title: "Trace Errors",
      metadata: {
        "type" => "skill",
        "confidence" => "high",
        "tags" => ["debugging", "errors"],
        "domain" => "debugging",
        "source" => "experimentation",
      },
    )

    @storage.write(
      file_path: "fact/people/jane.md",
      content: "# Jane Smith\n\nSenior developer on the backend team.",
      title: "Jane Smith",
      metadata: {
        "type" => "fact",
        "confidence" => "high",
        "tags" => ["people", "team"],
        "domain" => "people",
        "source" => "user",
      },
    )

    # Track initial embedding call count
    initial_call_count = @embedder.call_count

    # Verify entries exist with embeddings
    assert_equal(3, @adapter.all_entries.size)
    @adapter.all_entries.each do |_path, entry|
      assert_predicate(entry, :embedded?, "Entry should have embedding")
    end

    # Simulate rebuild: iterate through all entries and re-write them
    # This is exactly what the CLI rebuild command does
    rebuild_count = 0
    @adapter.all_entries.each do |path, entry|
      @storage.write(
        file_path: path,
        content: entry.content,
        title: entry.title,
        metadata: entry.metadata,
        generate_embedding: true,
      )
      rebuild_count += 1
    end

    # Verify rebuild processed all entries
    assert_equal(3, rebuild_count)

    # Verify embeddings were regenerated (embedder called again for each entry)
    assert_equal(initial_call_count + 3, @embedder.call_count)

    # Verify all entries still have embeddings
    @adapter.all_entries.each do |_path, entry|
      assert_predicate(entry, :embedded?, "Entry should still have embedding after rebuild")
    end
  end

  def test_rebuild_preserves_content_and_metadata
    # Write an entry
    original_content = "# Test Entry\n\nOriginal content here."
    original_metadata = {
      "type" => "concept",
      "confidence" => "high",
      "tags" => ["test", "rebuild"],
      "domain" => "testing",
      "source" => "user",
    }

    @storage.write(
      file_path: "test/preserve.md",
      content: original_content,
      title: "Test Entry",
      metadata: original_metadata,
    )

    # Get the entry
    entry = @adapter.all_entries["test/preserve.md"]

    # Rebuild it
    @storage.write(
      file_path: "test/preserve.md",
      content: entry.content,
      title: entry.title,
      metadata: entry.metadata,
      generate_embedding: true,
    )

    # Verify content and metadata are preserved
    rebuilt_entry = @adapter.read_entry(file_path: "test/preserve.md")

    assert_equal(original_content, rebuilt_entry.content)
    assert_equal(original_metadata["type"], rebuilt_entry.metadata["type"])
    assert_equal(original_metadata["tags"], rebuilt_entry.metadata["tags"])
    assert_equal(original_metadata["domain"], rebuilt_entry.metadata["domain"])
  end

  def test_rebuild_handles_entries_without_embeddings
    # Create storage without embedder
    storage_no_embedder = SwarmMemory::Core::Storage.new(adapter: @adapter)

    # Write entry without embedding
    storage_no_embedder.write(
      file_path: "test/no-embed.md",
      content: "# No Embedding\n\nThis entry has no embedding.",
      title: "No Embedding",
      metadata: {
        "type" => "fact",
        "confidence" => "high",
        "tags" => ["test"],
        "domain" => "testing",
        "source" => "user",
      },
    )

    # Verify no embedding
    entry = @adapter.read_entry(file_path: "test/no-embed.md")

    refute_predicate(entry, :embedded?, "Entry should not have embedding")

    # Now rebuild with embedder (simulating CLI rebuild command)
    @storage.write(
      file_path: "test/no-embed.md",
      content: entry.content,
      title: entry.title,
      metadata: entry.metadata,
      generate_embedding: true,
    )

    # Verify embedding was added
    rebuilt_entry = @adapter.read_entry(file_path: "test/no-embed.md")

    assert_predicate(rebuilt_entry, :embedded?, "Entry should now have embedding")
  end

  # Mock embedder for testing
  class MockEmbedder
    attr_reader :call_count

    def initialize
      @call_count = 0
      @dimension = 384
    end

    def embed(text)
      @call_count += 1
      # Return a simple mock embedding (384 dimensions)
      Array.new(@dimension) { rand }
    end

    def dimensions
      @dimension
    end
  end
end
