# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class TextSimilarityTest < Minitest::Test
  def test_jaccard_identical_texts
    text = "ruby testing framework minitest"
    similarity = SwarmMemory::Search::TextSimilarity.jaccard(text, text)

    assert_in_delta(1.0, similarity)
  end

  def test_jaccard_no_overlap
    text1 = "ruby testing"
    text2 = "python framework"
    similarity = SwarmMemory::Search::TextSimilarity.jaccard(text1, text2)

    assert_in_delta(0.0, similarity)
  end

  def test_jaccard_partial_overlap
    text1 = "ruby testing framework"
    text2 = "ruby programming language"
    # Words: {ruby, testing, framework} vs {ruby, programming, language}
    # Intersection: {ruby} = 1
    # Union: {ruby, testing, framework, programming, language} = 5
    # Similarity: 1/5 = 0.2
    similarity = SwarmMemory::Search::TextSimilarity.jaccard(text1, text2)

    assert_in_delta(0.2, similarity, 0.01)
  end

  def test_jaccard_case_insensitive
    text1 = "Ruby Testing"
    text2 = "ruby testing"
    similarity = SwarmMemory::Search::TextSimilarity.jaccard(text1, text2)

    assert_in_delta(1.0, similarity)
  end

  def test_cosine_identical_vectors
    vec = [1.0, 2.0, 3.0]
    similarity = SwarmMemory::Search::TextSimilarity.cosine(vec, vec)

    assert_in_delta(1.0, similarity)
  end

  def test_cosine_orthogonal_vectors
    vec1 = [1.0, 0.0, 0.0]
    vec2 = [0.0, 1.0, 0.0]
    similarity = SwarmMemory::Search::TextSimilarity.cosine(vec1, vec2)

    assert_in_delta(0.0, similarity)
  end

  def test_cosine_similar_vectors
    vec1 = [1.0, 2.0, 3.0]
    vec2 = [2.0, 4.0, 6.0] # Same direction, different magnitude
    similarity = SwarmMemory::Search::TextSimilarity.cosine(vec1, vec2)

    assert_in_delta(1.0, similarity, 0.0001)
  end

  def test_cosine_different_length_raises_error
    vec1 = [1.0, 2.0]
    vec2 = [1.0, 2.0, 3.0]
    error = assert_raises(ArgumentError) do
      SwarmMemory::Search::TextSimilarity.cosine(vec1, vec2)
    end
    assert_match(/same length/, error.message)
  end
end
