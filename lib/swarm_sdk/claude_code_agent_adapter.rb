# frozen_string_literal: true

module SwarmSDK
  # Adapter for converting Claude Code agent markdown files to SwarmSDK format
  #
  # Claude Code agent files use a different syntax and conventions than SwarmSDK:
  # - Tools are comma-separated strings instead of arrays
  # - Model shortcuts like 'sonnet', 'opus', 'haiku' instead of full model IDs
  # - Tool permissions like 'Write(src/**)' instead of SwarmSDK's permission system
  # - Required 'name' field in frontmatter
  #
  # This adapter:
  # - Detects Claude Code format by checking frontmatter markers
  # - Converts tools from comma-separated strings to arrays
  # - Maps model shortcuts to canonical model IDs
  # - Strips unsupported tool permission syntax with warnings
  # - Sets coding_agent: true by default
  # - Warns about unsupported fields
  #
  # @example Parse a Claude Code agent file
  #   content = File.read('.claude/agents/reviewer.md')
  #   config = ClaudeCodeAgentAdapter.parse(content, :reviewer)
  #   agent = Agent::Definition.new(:reviewer, config)
  #
  class ClaudeCodeAgentAdapter
    # Fields supported in Claude Code agent frontmatter
    SUPPORTED_FIELDS = ["name", "description", "tools", "model"].freeze

    # SwarmSDK documentation URL for reference
    SWARM_SDK_DOCS_URL = "https://github.com/parruda/claude-swarm/blob/main/docs/v2/README.md"

    # Pattern to detect tool permission syntax like Write(src/**)
    TOOL_PERMISSION_PATTERN = /^([A-Za-z_]+)\([^)]+\)$/

    class << self
      # Detect if content appears to be in Claude Code agent format
      #
      # Detection is based on tools field type:
      # - Claude Code: tools is a comma-separated string (e.g., "Read, Write, Bash")
      # - SwarmSDK: tools is an array (e.g., [Read, Write, Bash])
      #
      # Note: The 'name' field alone is not sufficient since SwarmSDK also supports it
      #
      # @param content [String] Markdown content with YAML frontmatter
      # @return [Boolean] true if content appears to be Claude Code format
      def claude_code_format?(content)
        return false unless content =~ /\A---\s*\n(.*?)\n---\s*\n/m

        frontmatter_yaml = Regexp.last_match(1)
        frontmatter = YAML.safe_load(frontmatter_yaml, permitted_classes: [Symbol], aliases: true)

        return false unless frontmatter.is_a?(Hash)

        # Only detect as Claude Code if tools field is a comma-separated string
        # This is the most reliable indicator since SwarmSDK always uses arrays
        frontmatter.key?("tools") && frontmatter["tools"].is_a?(String)
      rescue Psych::SyntaxError
        false
      end

      # Parse Claude Code agent markdown and convert to SwarmSDK format
      #
      # @param content [String] Markdown content with YAML frontmatter
      # @param agent_name [Symbol, String] Name of the agent
      # @param inherit_model [String, nil] Model to use when frontmatter has 'inherit'
      # @return [Hash] Configuration hash suitable for Agent::Definition.new
      # @raise [ConfigurationError] if content format is invalid
      def parse(content, agent_name, inherit_model: nil)
        new(inherit_model: inherit_model).parse(content, agent_name)
      end
    end

    # Initialize adapter with optional context
    #
    # @param inherit_model [String, nil] Model to use when frontmatter has 'inherit'
    def initialize(inherit_model: nil)
      @inherit_model = inherit_model
      @warnings = []
    end

    # Parse Claude Code agent content
    #
    # @param content [String] Markdown content with YAML frontmatter
    # @param agent_name [Symbol, String] Name of the agent
    # @return [Hash] Configuration hash for Agent::Definition
    # @raise [ConfigurationError] if format is invalid
    def parse(content, agent_name)
      unless content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m
        raise ConfigurationError, "Invalid Claude Code agent format. Expected YAML frontmatter followed by prompt content."
      end

      frontmatter_yaml = Regexp.last_match(1)
      prompt_content = Regexp.last_match(2).strip

      frontmatter = YAML.safe_load(frontmatter_yaml, permitted_classes: [Symbol], aliases: true)

      unless frontmatter.is_a?(Hash)
        raise ConfigurationError, "Invalid frontmatter format in Claude Code agent file"
      end

      config = build_config(frontmatter, prompt_content, agent_name)
      emit_warnings(agent_name)
      config
    end

    private

    # Build SwarmSDK configuration from Claude Code frontmatter
    def build_config(frontmatter, prompt_content, agent_name)
      warn_unknown_fields(frontmatter)

      config = {
        description: frontmatter["description"],
        system_prompt: prompt_content,
        coding_agent: true, # Default for Claude Code agents
      }

      # Parse tools if present
      if frontmatter["tools"]
        config[:tools] = parse_tools(frontmatter["tools"])
      end

      # Parse model if present
      if frontmatter["model"]
        config[:model] = resolve_model(frontmatter["model"])
      end

      config
    end

    # Parse tools field - handles both comma-separated string and array
    #
    # @param tools_field [String, Array] Tools from frontmatter
    # @return [Array<String>] Array of tool names
    def parse_tools(tools_field)
      tools_array = if tools_field.is_a?(String)
        tools_field.split(",").map(&:strip)
      else
        Array(tools_field).map(&:to_s)
      end

      # Clean tool permissions and collect warnings
      tools_array.map { |tool| clean_tool_permissions(tool) }.compact
    end

    # Strip tool permission syntax and warn if detected
    #
    # @param tool_string [String] Tool name, possibly with permissions like 'Write(src/**)'
    # @return [String, nil] Clean tool name, or nil if invalid
    def clean_tool_permissions(tool_string)
      if tool_string =~ TOOL_PERMISSION_PATTERN
        tool_name = Regexp.last_match(1)
        @warnings << "Tool permission syntax '#{tool_string}' detected in agent file. SwarmSDK supports permissions but uses different syntax. Using '#{tool_name}' without restrictions for now. See SwarmSDK documentation for permission configuration: #{SWARM_SDK_DOCS_URL}"
        tool_name
      else
        tool_string
      end
    end

    # Resolve model shortcuts to canonical model IDs
    #
    # Uses SwarmSDK::Models.resolve_alias to map shortcuts like 'sonnet'
    # to the latest model IDs from model_aliases.json.
    #
    # @param model_field [String] Model from frontmatter
    # @return [String, Symbol] Canonical model ID or :inherit symbol
    def resolve_model(model_field)
      model_str = model_field.to_s.strip

      # Handle 'inherit' keyword
      return :inherit if model_str == "inherit"

      # Resolve using SwarmSDK model aliases
      # This maps 'sonnet' → 'claude-sonnet-4-5-20250929', etc.
      SwarmSDK::Models.resolve_alias(model_str)
    end

    # Warn about unknown frontmatter fields
    def warn_unknown_fields(frontmatter)
      unknown_fields = frontmatter.keys - SUPPORTED_FIELDS

      unknown_fields.each do |field|
        @warnings << case field
        when "hooks"
          "Hooks configuration detected in agent frontmatter. SwarmSDK handles hooks at the swarm level. See: #{SWARM_SDK_DOCS_URL}"
        else
          "Unknown field '#{field}' in Claude Code agent file. Ignoring. Supported fields: #{SUPPORTED_FIELDS.join(", ")}"
        end
      end
    end

    # Emit all collected warnings via LogCollector
    def emit_warnings(agent_name)
      return if @warnings.empty?

      @warnings.each do |warning|
        LogCollector.emit(
          type: "claude_code_conversion_warning",
          agent: agent_name,
          message: warning,
        )
      end
    end
  end
end
