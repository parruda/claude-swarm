# frozen_string_literal: true

module SwarmMemory
  module Core
    # Represents a single memory entry with metadata and optional embedding
    #
    # @attr content [String] The actual content stored
    # @attr title [String] Brief description of the content
    # @attr updated_at [Time] Last modification timestamp
    # @attr size [Integer] Content size in bytes
    # @attr embedding [Array<Float>, nil] Optional 384-dim embedding vector
    # @attr metadata [Hash, nil] Optional parsed frontmatter metadata
    Entry = Struct.new(
      :content,
      :title,
      :updated_at,
      :size,
      :embedding,
      :metadata,
      keyword_init: true,
    ) do
      # Check if entry has an embedding
      #
      # @return [Boolean]
      def embedded?
        !embedding.nil? && !embedding.empty?
      end

      # Check if entry has metadata
      #
      # @return [Boolean]
      def has_metadata?
        !metadata.nil? && !metadata.empty?
      end
    end
  end
end
