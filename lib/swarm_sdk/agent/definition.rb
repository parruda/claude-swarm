# frozen_string_literal: true

module SwarmSDK
  module Agent
    # Agent definition encapsulates agent configuration and builds system prompts
    #
    # This class is responsible for:
    # - Parsing and validating agent configuration
    # - Building the full system prompt (base + custom)
    # - Handling tool permissions
    # - Managing hooks (both DSL Ruby blocks and YAML shell commands)
    #
    # @example
    #   definition = Agent::Definition.new(:backend, {
    #     description: "Backend API developer",
    #     model: "gpt-5",
    #     tools: [:Read, :Write, :Bash],
    #     system_prompt: "You build APIs"
    #   })
    class Definition
      DEFAULT_MODEL = "gpt-5"
      DEFAULT_PROVIDER = "openai"
      DEFAULT_TIMEOUT = 300 # 5 minutes - reasoning models can take a while
      BASE_SYSTEM_PROMPT_PATH = File.expand_path("../prompts/base_system_prompt.md.erb", __dir__)

      attr_reader :name,
        :description,
        :model,
        :context_window,
        :directory,
        :tools,
        :delegates_to,
        :system_prompt,
        :provider,
        :base_url,
        :api_version,
        :mcp_servers,
        :parameters,
        :headers,
        :timeout,
        :include_default_tools,
        :enable_think_tool,
        :coding_agent,
        :default_permissions,
        :agent_permissions,
        :assume_model_exists,
        :hooks

      attr_accessor :bypass_permissions, :max_concurrent_tools

      def initialize(name, config = {})
        @name = name.to_sym

        # BREAKING CHANGE: Hard error for plural form
        if config[:directories]
          raise ConfigurationError,
            "The 'directories' (plural) configuration is no longer supported in SwarmSDK 1.0+.\n\n" \
              "Change 'directories:' to 'directory:' (singular).\n\n" \
              "If you need access to multiple directories, use permissions:\n\n  " \
              "directory: 'backend/'\n  " \
              "permissions do\n    " \
              "tool(:Read).allow_paths('../shared/**')\n  " \
              "end"
        end

        @description = config[:description]
        @model = config[:model] || DEFAULT_MODEL
        @provider = config[:provider] || DEFAULT_PROVIDER
        @base_url = config[:base_url]
        @api_version = config[:api_version]
        @context_window = config[:context_window] # Explicit context window override
        @parameters = config[:parameters] || {}
        @headers = Utils.stringify_keys(config[:headers] || {})
        @timeout = config[:timeout] || DEFAULT_TIMEOUT
        @bypass_permissions = config[:bypass_permissions] || false
        @max_concurrent_tools = config[:max_concurrent_tools]
        # Always assume model exists - SwarmSDK validates models separately using models.json
        # This prevents RubyLLM from trying to validate models in its registry
        @assume_model_exists = true

        # include_default_tools defaults to true if not specified
        @include_default_tools = config.key?(:include_default_tools) ? config[:include_default_tools] : true

        # enable_think_tool defaults to true if not specified
        # When true, includes the Think tool (for explicit reasoning)
        # When false, excludes the Think tool even if default tools are enabled
        @enable_think_tool = config.key?(:enable_think_tool) ? config[:enable_think_tool] : true

        # coding_agent defaults to false if not specified
        # When true, includes the base system prompt for coding tasks
        # When false, uses only the custom system prompt (no base prompt)
        @coding_agent = config.key?(:coding_agent) ? config[:coding_agent] : false

        # Parse directory first so it can be used in system prompt rendering
        @directory = parse_directory(config[:directory])

        # Build system prompt after directory is set
        @system_prompt = build_full_system_prompt(config[:system_prompt])

        # Parse tools with permissions support
        @default_permissions = config[:default_permissions] || {}
        @agent_permissions = config[:permissions] || {}
        @tools = parse_tools_with_permissions(
          config[:tools],
          @default_permissions,
          @agent_permissions,
        )

        # Inject default write restrictions for security
        @tools = inject_default_write_permissions(@tools)

        @delegates_to = Array(config[:delegates_to] || []).map(&:to_sym)
        @mcp_servers = Array(config[:mcp_servers] || [])

        # Parse hooks configuration
        # Handles both DSL (HookDefinition objects) and YAML (raw hash) formats
        @hooks = parse_hooks(config[:hooks])

        validate!
      end

      def to_h
        {
          name: @name,
          description: @description,
          model: SwarmSDK::Models.resolve_alias(@model), # Resolve model aliases
          directory: @directory,
          tools: @tools,
          delegates_to: @delegates_to,
          system_prompt: @system_prompt,
          provider: @provider,
          base_url: @base_url,
          api_version: @api_version,
          mcp_servers: @mcp_servers,
          parameters: @parameters,
          headers: @headers,
          timeout: @timeout,
          bypass_permissions: @bypass_permissions,
          include_default_tools: @include_default_tools,
          enable_think_tool: @enable_think_tool,
          coding_agent: @coding_agent,
          assume_model_exists: @assume_model_exists,
          max_concurrent_tools: @max_concurrent_tools,
          hooks: @hooks,
        }.compact
      end

      # Validate agent configuration and return warnings (non-fatal issues)
      #
      # Unlike validate! which raises exceptions for critical errors, this method
      # returns an array of warning hashes for non-fatal issues like:
      # - Model not found in registry (informs user, suggests alternatives)
      # - Context tracking unavailable (useful even with assume_model_exists)
      #
      # Note: Validation ALWAYS runs, even with assume_model_exists: true or base_url set.
      # The purpose is to inform the user about potential issues and suggest corrections,
      # not to block execution.
      #
      # @return [Array<Hash>] Array of warning hashes
      def validate
        warnings = []

        # Always validate model (even with assume_model_exists)
        # Warnings inform user about typos and context tracking limitations
        model_warning = validate_model
        warnings << model_warning if model_warning

        # Future: could add tool validation, delegate validation, etc.

        warnings
      end

      private

      # Validate that model exists in SwarmSDK's model registry
      #
      # Uses SwarmSDK's static models.json instead of RubyLLM's dynamic registry.
      # This provides stable, offline model validation without network calls.
      #
      # Process:
      # 1. Try to find model directly in models.json
      # 2. If not found, try to resolve as alias and find again
      # 3. If still not found, return warning with suggestions
      #
      # @return [Hash, nil] Warning hash if model not found, nil otherwise
      def validate_model
        # Try direct lookup first
        model_data = SwarmSDK::Models.all.find { |m| (m["id"] || m[:id]) == @model }

        # If not found, try alias resolution
        unless model_data
          resolved_id = SwarmSDK::Models.resolve_alias(@model)
          # Only search again if alias was different
          if resolved_id != @model
            model_data = SwarmSDK::Models.all.find { |m| (m["id"] || m[:id]) == resolved_id }
          end
        end

        if model_data
          nil # Model exists (either directly or via alias)
        else
          # Model not found - return warning with suggestions
          {
            type: :model_not_found,
            agent: @name,
            model: @model,
            error_message: "Unknown model: #{@model}",
            suggestions: SwarmSDK::Models.suggest_similar(@model),
          }
        end
      rescue StandardError => e
        # Return warning on error
        {
          type: :model_not_found,
          agent: @name,
          model: @model,
          error_message: e.message,
          suggestions: [],
        }
      end

      def build_full_system_prompt(custom_prompt)
        # If coding_agent is false (default), return custom prompt with optional TODO/Scratchpad info
        # If coding_agent is true, include full base prompt for coding tasks
        if @coding_agent
          # Coding agent: include full base prompt
          rendered_base = render_base_system_prompt

          if custom_prompt && !custom_prompt.strip.empty?
            "#{rendered_base}\n\n#{custom_prompt}"
          else
            rendered_base
          end
        elsif @include_default_tools
          # Non-coding agent: optionally include TODO/Scratchpad sections if default tools available
          non_coding_base = render_non_coding_base_prompt

          if custom_prompt && !custom_prompt.strip.empty?
            # Prepend TODO/Scratchpad info before custom prompt
            "#{non_coding_base}\n\n#{custom_prompt}"
          else
            # No custom prompt: just return TODO/Scratchpad info
            non_coding_base
          end
        # Default tools available: include TODO/Scratchpad instructions
        else
          # No default tools: return only custom prompt
          (custom_prompt || "").to_s
        end
      end

      def render_base_system_prompt
        cwd = @directory || Dir.pwd
        platform = RUBY_PLATFORM
        os_version = begin
          %x(uname -sr 2>/dev/null).strip
        rescue
          RUBY_PLATFORM
        end
        date = Time.now.strftime("%Y-%m-%d")

        template_content = File.read(BASE_SYSTEM_PROMPT_PATH)
        ERB.new(template_content).result(binding)
      end

      def render_non_coding_base_prompt
        # Simplified base prompt for non-coding agents
        # Includes environment info, TODO, and Scratchpad tool information
        # Does not steer towards coding tasks
        cwd = @directory || Dir.pwd
        platform = RUBY_PLATFORM
        os_version = begin
          %x(uname -sr 2>/dev/null).strip
        rescue
          RUBY_PLATFORM
        end
        date = Time.now.strftime("%Y-%m-%d")

        <<~PROMPT.strip
          # Environment

          <env>
          Working directory: #{cwd}
          Platform: #{platform}
          OS Version: #{os_version}
          Today's date: #{date}
          </env>

          # Task Management

          You have access to the TodoWrite tool to help you manage and plan tasks. Use this tool to track your progress and give visibility into your work.

          When working on multi-step tasks:
          1. Create a todo list with all known tasks before starting work
          2. Mark each task as in_progress when you start it
          3. Mark each task as completed IMMEDIATELY after finishing it
          4. Complete ALL pending todos before finishing your response

          # Scratchpad Storage

          You have access to Scratchpad tools for storing and retrieving information:
          - **ScratchpadWrite**: Store detailed outputs, analysis, or results that are too long for direct responses
          - **ScratchpadRead**: Retrieve previously stored content
          - **ScratchpadList**: List available scratchpad entries

          Use the scratchpad to share information that would otherwise clutter your responses.
        PROMPT
      end

      def parse_directory(directory_config)
        directory_config ||= "."
        File.expand_path(directory_config.to_s)
      end

      # Parse tools configuration with permissions support
      #
      # Tools can be specified as:
      # - Symbol: :Write (no permissions)
      # - Hash: { Write: { allowed_paths: [...] } } (with permissions)
      #
      # Returns array of tool configs:
      # [
      #   { name: :Read, permissions: nil },
      #   { name: :Write, permissions: { allowed_paths: [...] } }
      # ]
      def parse_tools_with_permissions(tools_config, default_permissions, agent_permissions)
        tools_array = Array(tools_config || [])

        tools_array.map do |tool_spec|
          case tool_spec
          when Symbol, String
            # Simple tool: :Write or "Write"
            tool_name = tool_spec.to_sym
            permissions = resolve_permissions(tool_name, default_permissions, agent_permissions)

            { name: tool_name, permissions: permissions }
          when Hash
            # Check if already in parsed format: { name: :Write, permissions: {...} }
            if tool_spec.key?(:name)
              # Already parsed - pass through as-is
              tool_spec
            else
              # Tool with inline permissions: { Write: { allowed_paths: [...] } }
              tool_name = tool_spec.keys.first.to_sym
              inline_permissions = tool_spec.values.first

              # Inline permissions override defaults
              { name: tool_name, permissions: inline_permissions }
            end
          else
            raise ConfigurationError, "Invalid tool specification: #{tool_spec.inspect}"
          end
        end
      end

      # Resolve permissions for a tool from defaults and agent-level overrides
      def resolve_permissions(tool_name, default_permissions, agent_permissions)
        # Agent-level permissions override defaults
        agent_permissions[tool_name] || default_permissions[tool_name]
      end

      # Inject default write permissions for security
      #
      # Write, Edit, and MultiEdit tools without explicit permissions are automatically
      # restricted to only write within the agent's directory. This prevents accidental
      # writes outside the agent's working scope.
      #
      # Default permission: { allowed_paths: ["**/*"] }
      # This is resolved relative to the agent's directory by the permissions system.
      #
      # Users can override by explicitly setting permissions for these tools.
      def inject_default_write_permissions(tools)
        write_tools = [:Write, :Edit, :MultiEdit]

        tools.map do |tool_config|
          tool_name = tool_config[:name]

          # If it's a write tool and has no permissions, inject default
          if write_tools.include?(tool_name) && tool_config[:permissions].nil?
            tool_config.merge(permissions: { allowed_paths: ["**/*"] })
          else
            tool_config
          end
        end
      end

      # Parse hooks configuration
      #
      # Handles two input formats:
      #
      # 1. DSL format (from Agent::Builder): Pre-parsed HookDefinition objects
      #    { event_type: [HookDefinition, ...] }
      #    These are applied directly in pass_4_configure_hooks
      #
      # 2. YAML format: Raw hash with shell command specifications
      #    hooks:
      #      pre_tool_use:
      #        - matcher: "Write|Edit"
      #          type: command
      #          command: "validate.sh"
      #    These are kept raw and processed by Hooks::Adapter in pass_5
      #
      # Returns:
      # - DSL: { event_type: [HookDefinition, ...] }
      # - YAML: Raw hash (for Hooks::Adapter)
      def parse_hooks(hooks_config)
        return {} if hooks_config.nil? || hooks_config.empty?

        # If already parsed from DSL (HookDefinition objects), return as-is
        if hooks_config.is_a?(Hash) && hooks_config.values.all? { |v| v.is_a?(Array) && v.all? { |item| item.is_a?(Hooks::Definition) } }
          return hooks_config
        end

        # For YAML hooks: validate structure but keep raw for Hooks::Adapter
        validate_yaml_hooks(hooks_config)

        # Return raw YAML - Hooks::Adapter will process in pass_5
        hooks_config
      end

      # Validate YAML hooks structure
      #
      # @param hooks_config [Hash] YAML hooks configuration
      # @return [void]
      def validate_yaml_hooks(hooks_config)
        hooks_config.each do |event_name, hook_specs|
          event_sym = event_name.to_sym

          # Validate event type
          unless Hooks::Registry::VALID_EVENTS.include?(event_sym)
            raise ConfigurationError,
              "Invalid hook event '#{event_name}' for agent '#{@name}'. " \
                "Valid events: #{Hooks::Registry::VALID_EVENTS.join(", ")}"
          end

          # Validate each hook spec structure
          Array(hook_specs).each do |spec|
            hook_type = spec[:type] || spec["type"]
            command = spec[:command] || spec["command"]

            raise ConfigurationError, "Hook missing 'type' field for event #{event_name}" unless hook_type
            raise ConfigurationError, "Hook missing 'command' field for event #{event_name}" if hook_type.to_s == "command" && !command
          end
        end
      end

      def validate!
        raise ConfigurationError, "Agent '#{@name}' missing required 'description' field" unless @description

        # Validate api_version can only be set for OpenAI-compatible providers
        if @api_version
          openai_compatible = ["openai", "deepseek", "perplexity", "mistral", "openrouter"]
          unless openai_compatible.include?(@provider.to_s)
            raise ConfigurationError,
              "Agent '#{@name}' has api_version set, but provider is '#{@provider}'. " \
                "api_version can only be used with OpenAI-compatible providers: #{openai_compatible.join(", ")}"
          end

          # Validate api_version value
          valid_versions = ["v1/chat/completions", "v1/responses"]
          unless valid_versions.include?(@api_version)
            raise ConfigurationError,
              "Agent '#{@name}' has invalid api_version '#{@api_version}'. " \
                "Valid values: #{valid_versions.join(", ")}"
          end
        end

        unless File.directory?(@directory)
          raise ConfigurationError, "Directory '#{@directory}' for agent '#{@name}' does not exist"
        end
      end
    end
  end
end
