# frozen_string_literal: true

module SwarmMemory
  module Core
    # Extracts structured metadata from memory entries
    #
    # This class wraps FrontmatterParser and provides additional
    # metadata extraction logic specific to the memory system.
    class MetadataExtractor
      class << self
        # Extract all metadata from a memory entry
        #
        # @param content [String] Full entry content
        # @return [Hash] Extracted metadata
        #
        # @example
        #   metadata = MetadataExtractor.extract(content)
        #   metadata[:confidence] # => "high"
        #   metadata[:type] # => "concept"
        #   metadata[:tags] # => ["ruby", "testing"]
        def extract(content)
          FrontmatterParser.extract_metadata(content)
        end

        # Check if entry has required frontmatter for quality
        #
        # @param content [String] Full entry content
        # @return [Boolean] True if entry has basic required fields
        def has_required_frontmatter?(content)
          metadata = extract(content)
          !metadata[:type].nil? && !metadata[:confidence].nil?
        end

        # Calculate entry quality score (0-100)
        #
        # @param content [String] Full entry content
        # @return [Integer] Quality score
        def quality_score(content)
          metadata = extract(content)
          score = 0

          # Has type (20 points)
          score += 20 if metadata[:type]

          # Has confidence (20 points)
          score += 20 if metadata[:confidence]

          # Has tags (15 points)
          score += 15 unless metadata[:tags].empty?

          # Has related links (15 points)
          score += 15 unless metadata[:related].empty?

          # Has domain (10 points)
          score += 10 if metadata[:domain]

          # Has last_verified (10 points)
          score += 10 if metadata[:last_verified]

          # High confidence bonus (10 points)
          score += 10 if metadata[:confidence] == "high"

          score
        end
      end
    end
  end
end
