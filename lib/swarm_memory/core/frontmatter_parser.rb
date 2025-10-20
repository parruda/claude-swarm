# frozen_string_literal: true

module SwarmMemory
  module Core
    # Parser for YAML frontmatter in memory entries
    #
    # Parses markdown content with YAML frontmatter:
    #   ---
    #   type: concept
    #   confidence: high
    #   tags: [ruby, testing]
    #   ---
    #
    #   # Title
    #   Content here...
    class FrontmatterParser
      # Regex pattern to match frontmatter (same as MarkdownParser)
      FRONTMATTER_PATTERN = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

      class << self
        # Parse content and extract frontmatter
        #
        # @param content [String] Full entry content
        # @return [Hash] { frontmatter: Hash, body: String, error: nil|String }
        #
        # @example
        #   parsed = FrontmatterParser.parse("---\ntype: fact\n---\nContent")
        #   parsed[:frontmatter] # => { type: "fact" }
        #   parsed[:body] # => "Content"
        def parse(content)
          return { frontmatter: {}, body: content, error: nil } if content.nil? || content.empty?

          if content =~ FRONTMATTER_PATTERN
            frontmatter_yaml = Regexp.last_match(1)
            body = Regexp.last_match(2)

            begin
              frontmatter = YAML.safe_load(frontmatter_yaml, permitted_classes: [Symbol, Date, Time], aliases: true)
              frontmatter = symbolize_keys(frontmatter) if frontmatter.is_a?(Hash)
              { frontmatter: frontmatter || {}, body: body, error: nil }
            rescue StandardError => e
              # If YAML parsing fails, treat as body without frontmatter
              { frontmatter: {}, body: content, error: e.message }
            end
          else
            # No frontmatter
            { frontmatter: {}, body: content, error: nil }
          end
        end

        # Extract specific metadata fields from frontmatter
        #
        # @param content [String] Full entry content
        # @return [Hash] Extracted metadata fields
        #
        # @example
        #   metadata = FrontmatterParser.extract_metadata(content)
        #   metadata[:confidence] # => "high"
        #   metadata[:type] # => "concept"
        def extract_metadata(content)
          parsed = parse(content)
          fm = parsed[:frontmatter]

          {
            confidence: fm[:confidence]&.to_s&.downcase, # "high", "medium", "low"
            type: fm[:type]&.to_s&.downcase, # "concept", "fact", "skill", "experience"
            tags: Array(fm[:tags] || []),
            last_verified: parse_date(fm[:last_verified]),
            related: Array(fm[:related] || []),
            domain: fm[:domain]&.to_s,
            source: fm[:source]&.to_s,
          }
        end

        private

        # Parse date from various formats
        #
        # @param value [String, Date, Time, nil] Date value
        # @return [Date, nil]
        def parse_date(value)
          return if value.nil?
          return value.to_date if value.is_a?(Time)
          return value if value.is_a?(Date)

          Date.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        # Recursively symbolize hash keys
        #
        # @param obj [Object] Object to symbolize
        # @return [Object] Object with symbolized keys
        def symbolize_keys(obj)
          case obj
          when Hash
            obj.transform_keys(&:to_sym).transform_values { |v| symbolize_keys(v) }
          when Array
            obj.map { |item| symbolize_keys(item) }
          else
            obj
          end
        end
      end
    end
  end
end
