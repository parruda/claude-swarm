# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class PathNormalizerTest < Minitest::Test
  def test_normalize_valid_path
    assert_equal("concepts/ruby/classes", SwarmMemory::Core::PathNormalizer.normalize("concepts/ruby/classes"))
    assert_equal("analysis/report", SwarmMemory::Core::PathNormalizer.normalize("analysis/report"))
  end

  def test_normalize_removes_trailing_slash
    assert_equal("concepts/ruby", SwarmMemory::Core::PathNormalizer.normalize("concepts/ruby/"))
  end

  def test_normalize_collapses_double_slashes
    assert_equal("concepts/ruby", SwarmMemory::Core::PathNormalizer.normalize("concepts//ruby"))
  end

  def test_rejects_parent_directory_references
    error = assert_raises(ArgumentError) do
      SwarmMemory::Core::PathNormalizer.normalize("../secrets")
    end
    assert_match(/invalid path/i, error.message)
  end

  def test_rejects_absolute_paths
    error = assert_raises(ArgumentError) do
      SwarmMemory::Core::PathNormalizer.normalize("/absolute/path")
    end
    assert_match(/invalid path/i, error.message)
  end

  def test_rejects_invalid_characters
    error = assert_raises(ArgumentError) do
      SwarmMemory::Core::PathNormalizer.normalize("concepts<>test")
    end
    assert_match(/invalid path/i, error.message)
  end

  def test_rejects_empty_path
    assert_raises(ArgumentError) do
      SwarmMemory::Core::PathNormalizer.normalize("")
    end
  end

  def test_rejects_nil_path
    assert_raises(ArgumentError) do
      SwarmMemory::Core::PathNormalizer.normalize(nil)
    end
  end

  def test_valid_returns_true_for_valid_path
    assert(SwarmMemory::Core::PathNormalizer.valid?("concepts/ruby"))
  end

  def test_valid_returns_false_for_invalid_path
    refute(SwarmMemory::Core::PathNormalizer.valid?("../invalid"))
    refute(SwarmMemory::Core::PathNormalizer.valid?("/absolute"))
  end
end
