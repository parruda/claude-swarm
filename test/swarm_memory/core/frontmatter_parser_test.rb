# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class FrontmatterParserTest < Minitest::Test
  def test_parse_with_frontmatter
    content = <<~CONTENT
      ---
      type: concept
      confidence: high
      tags: [ruby, testing]
      ---

      # Ruby Testing

      This is about testing in Ruby.
    CONTENT

    result = SwarmMemory::Core::FrontmatterParser.parse(content)

    assert_equal("concept", result[:frontmatter][:type])
    assert_equal("high", result[:frontmatter][:confidence])
    assert_equal(["ruby", "testing"], result[:frontmatter][:tags])
    assert_match(/# Ruby Testing/, result[:body])
    assert_nil(result[:error])
  end

  def test_parse_without_frontmatter
    content = "Just regular content without frontmatter"

    result = SwarmMemory::Core::FrontmatterParser.parse(content)

    assert_empty(result[:frontmatter])
    assert_equal(content, result[:body])
    assert_nil(result[:error])
  end

  def test_parse_with_invalid_yaml
    content = <<~CONTENT
      ---
      invalid: yaml: syntax: here
      ---

      Content
    CONTENT

    result = SwarmMemory::Core::FrontmatterParser.parse(content)

    assert_empty(result[:frontmatter])
    assert_equal(content, result[:body])
    assert(result[:error]) # Should have an error message
  end

  def test_extract_metadata
    content = <<~CONTENT
      ---
      type: skill
      confidence: medium
      tags: [debugging, ruby]
      last_verified: 2025-01-15
      related:
        - memory://concepts/ruby/classes.md
      domain: programming/ruby
      source: experimentation
      ---

      # How to Debug

      Steps for debugging.
    CONTENT

    metadata = SwarmMemory::Core::FrontmatterParser.extract_metadata(content)

    assert_equal("skill", metadata[:type])
    assert_equal("medium", metadata[:confidence])
    assert_equal(["debugging", "ruby"], metadata[:tags])
    assert_equal(Date.parse("2025-01-15"), metadata[:last_verified])
    assert_equal(["memory://concepts/ruby/classes.md"], metadata[:related])
    assert_equal("programming/ruby", metadata[:domain])
    assert_equal("experimentation", metadata[:source])
  end

  def test_extract_metadata_without_frontmatter
    content = "No frontmatter here"

    metadata = SwarmMemory::Core::FrontmatterParser.extract_metadata(content)

    assert_nil(metadata[:type])
    assert_nil(metadata[:confidence])
    assert_empty(metadata[:tags])
    assert_nil(metadata[:last_verified])
    assert_empty(metadata[:related])
  end
end
