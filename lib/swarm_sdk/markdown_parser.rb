# frozen_string_literal: true

module SwarmSDK
  # Parser for agent markdown files with YAML frontmatter
  #
  # Supports two formats:
  # 1. SwarmSDK format - YAML frontmatter with array-based tools
  # 2. Claude Code format - Detected and converted via ClaudeCodeAgentAdapter
  #
  # Format detection is automatic based on frontmatter structure.
  class MarkdownParser
    FRONTMATTER_PATTERN = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

    class << self
      # Parse markdown content into an Agent::Definition
      #
      # Automatically detects format (SwarmSDK or Claude Code) and routes
      # to appropriate parser.
      #
      # @param content [String] Markdown content with YAML frontmatter
      # @param agent_name [Symbol, String, nil] Name of the agent
      # @return [Agent::Definition] Parsed agent definition
      # @raise [ConfigurationError] if format is invalid
      def parse(content, agent_name = nil)
        # Detect Claude Code format and route to adapter
        if ClaudeCodeAgentAdapter.claude_code_format?(content)
          config = ClaudeCodeAgentAdapter.parse(content, agent_name)
          # For Claude Code format, agent_name parameter is required since
          # the 'name' field in frontmatter is Claude Code specific and not used
          unless agent_name
            raise ConfigurationError, "Agent name must be provided when parsing Claude Code format"
          end

          Agent::Definition.new(agent_name.to_sym, config)
        else
          # Use standard SwarmSDK format parsing
          new(content, agent_name).parse
        end
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

        # Symbolize keys for AgentDefinition
        config = Utils.symbolize_keys(frontmatter).merge(system_prompt: prompt_content)

        name = @agent_name || frontmatter["name"]
        unless name
          raise ConfigurationError, "Agent definition must include 'name' in frontmatter or be specified externally"
        end

        # Convert name to symbol
        name = name.to_sym

        Agent::Definition.new(name, config)
      else
        raise ConfigurationError, "Invalid Markdown agent definition format. Expected YAML frontmatter followed by prompt content."
      end
    end
  end
end
