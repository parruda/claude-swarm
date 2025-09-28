# frozen_string_literal: true

module SwarmCore
  class MarkdownParser
    FRONTMATTER_PATTERN = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

    class << self
      def parse(content, agent_name = nil)
        new(content, agent_name).parse
      end
    end

    def initialize(content, agent_name = nil)
      @content = content
      @agent_name = agent_name
    end

    def parse
      if @content =~ FRONTMATTER_PATTERN
        frontmatter_yaml = Regexp.last_match(1)
        prompt_content = Regexp.last_match(2).strip

        frontmatter = YAML.safe_load(frontmatter_yaml, permitted_classes: [Symbol], aliases: true)

        unless frontmatter.is_a?(Hash)
          raise ConfigurationError, "Invalid frontmatter format in agent definition"
        end

        config = frontmatter.merge("prompt" => prompt_content)

        name = @agent_name || frontmatter["name"]
        unless name
          raise ConfigurationError, "Agent definition must include 'name' in frontmatter or be specified externally"
        end

        AgentConfig.new(name, config)
      else
        raise ConfigurationError, "Invalid Markdown agent definition format. Expected YAML frontmatter followed by prompt content."
      end
    end
  end
end
