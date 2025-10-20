# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class EntryTest < Minitest::Test
  def test_entry_creation
    entry = SwarmMemory::Core::Entry.new(
      content: "test content",
      title: "Test Entry",
      updated_at: Time.now,
      size: 12,
      embedding: nil,
      metadata: nil,
    )

    assert_equal("test content", entry.content)
    assert_equal("Test Entry", entry.title)
    assert_equal(12, entry.size)
    refute_predicate(entry, :embedded?)
    refute_predicate(entry, :has_metadata?)
  end

  def test_entry_with_embedding
    embedding = Array.new(384) { rand }
    entry = SwarmMemory::Core::Entry.new(
      content: "test",
      title: "Test",
      updated_at: Time.now,
      size: 4,
      embedding: embedding,
      metadata: nil,
    )

    assert_predicate(entry, :embedded?)
    assert_equal(384, entry.embedding.size)
  end

  def test_entry_with_metadata
    metadata = { type: "concept", confidence: "high" }
    entry = SwarmMemory::Core::Entry.new(
      content: "test",
      title: "Test",
      updated_at: Time.now,
      size: 4,
      embedding: nil,
      metadata: metadata,
    )

    assert_predicate(entry, :has_metadata?)
    assert_equal("concept", entry.metadata[:type])
  end
end
