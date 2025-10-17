# frozen_string_literal: true

module SwarmSDK
  # DSL builder for tool permissions configuration
  #
  # Provides fluent API for configuring tool permissions using underscore syntax:
  #
  # @example Basic usage
  #   permissions do
  #     tool(:Write).allow_paths "tmp/**/*"
  #     tool(:Write).deny_paths "tmp/secrets/**"
  #     tool(:Read).deny_paths "lib/**/*"
  #   end
  #
  # @example Bash commands
  #   permissions do
  #     tool(:Bash).allow_commands "^git (status|diff|log)$"
  #     tool(:Bash).deny_commands "^rm -rf"
  #   end
  #
  class PermissionsBuilder
    def initialize
      @permissions = {}
    end

    class << self
      # Build permissions from block
      #
      # @yield Block for configuring permissions
      # @return [Hash] Permissions configuration
      def build(&block)
        builder = new
        builder.instance_eval(&block)
        builder.to_h
      end
    end

    # Convert to hash format expected by AgentDefinition
    #
    # @return [Hash] Permissions config
    def to_h
      @permissions
    end

    # Get a tool permissions proxy for configuring a specific tool
    #
    # @param tool_name [Symbol, String] Tool name
    # @return [ToolPermissionsProxy] Proxy for configuring this tool
    #
    # @example
    #   tool(:Write).allow_paths "tmp/**/*"
    #   tool(:Bash).deny_commands "^rm -rf"
    def tool(tool_name)
      ToolPermissionsProxy.new(tool_name, @permissions)
    end
  end

  # Proxy for configuring permissions on a specific tool
  #
  # @example
  #   tool(:Write).allow_paths "tmp/**/*"
  #   tool(:Write).deny_paths "tmp/secrets/**"
  #   tool(:Bash).allow_commands "^git status$"
  #
  class ToolPermissionsProxy
    def initialize(tool_name, permissions_hash)
      @tool_name = tool_name.to_sym
      @permissions = permissions_hash
    end

    # Add allowed path patterns
    #
    # @param patterns [Array<String>] Glob patterns for allowed paths
    # @return [self]
    def allow_paths(*patterns)
      ensure_tool_config
      @permissions[@tool_name][:allowed_paths] ||= []
      @permissions[@tool_name][:allowed_paths].concat(patterns.flatten)
      self
    end

    # Add denied path patterns
    #
    # @param patterns [Array<String>] Glob patterns for denied paths
    # @return [self]
    def deny_paths(*patterns)
      ensure_tool_config
      @permissions[@tool_name][:denied_paths] ||= []
      @permissions[@tool_name][:denied_paths].concat(patterns.flatten)
      self
    end

    # Add allowed command patterns (Bash tool only)
    #
    # @param patterns [Array<String>] Regex patterns for allowed commands
    # @return [self]
    def allow_commands(*patterns)
      ensure_tool_config
      @permissions[@tool_name][:allowed_commands] ||= []
      @permissions[@tool_name][:allowed_commands].concat(patterns.flatten)
      self
    end

    # Add denied command patterns (Bash tool only)
    #
    # @param patterns [Array<String>] Regex patterns for denied commands
    # @return [self]
    def deny_commands(*patterns)
      ensure_tool_config
      @permissions[@tool_name][:denied_commands] ||= []
      @permissions[@tool_name][:denied_commands].concat(patterns.flatten)
      self
    end

    private

    # Ensure tool entry exists in permissions hash
    def ensure_tool_config
      @permissions[@tool_name] ||= {}
    end
  end
end
