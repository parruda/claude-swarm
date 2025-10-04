# frozen_string_literal: true

module ClaudeSwarm
  class FrontmatterParser
    FRONTMATTER_DELIMITER = "---"

    attr_reader :config, :content

    def initialize(file_path)
      @file_path = file_path
      parse_file
    end

    class << self
      def parse(file_path)
        new(file_path)
      end
    end

    private

    def parse_file
      file_content = File.read(@file_path)
      lines = file_content.lines

      # Check if file starts with frontmatter delimiter
      if lines.first&.strip != FRONTMATTER_DELIMITER
        raise ClaudeSwarm::Error, "Markdown instance file '#{@file_path}' must start with frontmatter delimiter (---)"
      end

      # Find the closing delimiter
      frontmatter_end = lines[1..].find_index { |line| line.strip == FRONTMATTER_DELIMITER }

      if frontmatter_end.nil?
        raise ClaudeSwarm::Error, "Markdown instance file '#{@file_path}' has unclosed frontmatter (missing closing ---)"
      end

      # Extract frontmatter and content
      frontmatter_lines = lines[1..frontmatter_end]
      content_lines = lines[(frontmatter_end + 2)..]

      # Parse YAML frontmatter
      frontmatter_yaml = frontmatter_lines.join
      begin
        @config = YAML.load(frontmatter_yaml, aliases: true)
        @config ||= {}

        # Validate that the frontmatter is a hash
        unless @config.is_a?(Hash)
          raise ClaudeSwarm::Error, "Frontmatter must be a YAML hash/object, got #{@config.class.name}"
        end
      rescue Psych::SyntaxError => e
        raise ClaudeSwarm::Error, "Invalid YAML in frontmatter of '#{@file_path}': #{e.message}"
      end

      # Store the markdown content (after frontmatter)
      @content = content_lines&.join || ""

      # If there's content and no prompt in config, use the content as prompt
      if !@content.strip.empty? && !@config.key?("prompt")
        @config["prompt"] = @content.strip
      end
    end
  end
end
