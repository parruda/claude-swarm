# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class DefragmenterTest < Minitest::Test
  def setup
    @temp_dir = File.join(Dir.tmpdir, "test-defrag-#{SecureRandom.hex(8)}")
    @adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)
    @defragmenter = SwarmMemory::Optimization::Defragmenter.new(adapter: @adapter)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  def test_health_report_empty_memory
    report = @defragmenter.health_report

    assert_match(/Total entries: 0/, report)
    assert_match(%r{Health Score: 0/100}, report)
  end

  def test_find_duplicates_with_high_similarity
    # Create very similar entries (more overlap for higher similarity)
    content1 = "Ruby is a dynamic programming language with elegant syntax for building applications"
    content2 = "Ruby is a dynamic programming language with elegant syntax for creating applications"

    @adapter.write(file_path: "concepts/ruby1.md", content: content1, title: "Ruby 1")
    @adapter.write(file_path: "concepts/ruby2.md", content: content2, title: "Ruby 2")

    # Use lower threshold since we're using Jaccard (word overlap)
    duplicates = @defragmenter.find_duplicates(threshold: 0.8)

    assert_equal(1, duplicates.size)
    assert_equal("concepts/ruby1.md", duplicates.first[:path1])
    assert_equal("concepts/ruby2.md", duplicates.first[:path2])
    assert_operator(duplicates.first[:similarity], :>=, 80)
  end

  def test_find_duplicates_no_matches
    @adapter.write(file_path: "concepts/ruby.md", content: "Ruby programming", title: "Ruby")
    @adapter.write(file_path: "concepts/python.md", content: "Python programming", title: "Python")

    duplicates = @defragmenter.find_duplicates(threshold: 0.9)

    assert_empty(duplicates)
  end

  def test_find_low_quality_missing_frontmatter
    @adapter.write(
      file_path: "no_frontmatter.md",
      content: "Just plain content without frontmatter",
      title: "No Frontmatter",
    )

    low_quality = @defragmenter.find_low_quality

    assert_equal(1, low_quality.size)
    assert_equal("no_frontmatter.md", low_quality.first[:path])
    assert_includes(low_quality.first[:issues], "No metadata")
  end

  def test_find_low_quality_with_proper_frontmatter
    # Create a complete entry with all required frontmatter
    content = <<~ENTRY
      ---
      type: concept
      confidence: high
      tags: [ruby, programming]
      related:
        - memory://concepts/oop
      ---

      # Ruby Concept

      This is a well-formed entry with all metadata.
    ENTRY

    @adapter.write(file_path: "concepts/ruby.md", content: content, title: "Ruby")

    low_quality = @defragmenter.find_low_quality(confidence_filter: "low")

    # Should not flag high-confidence entry with complete frontmatter
    # (unless embedder is present - then it would flag as "Not embedded")
    # For this test without embedder, it should not be flagged
    refute(low_quality.any? { |e| e[:path] == "concepts/ruby" && !e[:issues].include?("Not embedded") })
  end

  def test_find_archival_candidates
    # Create an entry
    @adapter.write(file_path: "test/entry.md", content: "test content", title: "Test Entry")

    # Use a very small age threshold (0 days) so any entry appears as a candidate
    # This tests the archival logic without needing to manipulate timestamps
    candidates = @defragmenter.find_archival_candidates(age_days: 0)

    # The entry should be flagged as a candidate
    assert_equal(1, candidates.size)
    assert_equal("test/entry.md", candidates.first[:path])
    assert_operator(candidates.first[:age_days], :>=, 0)
  end

  def test_full_analysis_report
    # Create some test entries
    @adapter.write(file_path: "entry1.md", content: create_sample_entry, title: "Entry 1")
    @adapter.write(file_path: "entry2.md", content: "no frontmatter", title: "Entry 2")

    report = @defragmenter.full_analysis

    assert_match(/Full Memory Defrag Analysis/, report)
    assert_match(/Memory Health Report/, report)
    # Report includes duplicate section (even if no duplicates found)
    assert_match(/duplicate/i, report)
    assert_match(/Low-Quality Entries/, report)
    # Report includes archival section (even if none found)
    assert_match(/older than|Archival Candidates/i, report)
  end
end
