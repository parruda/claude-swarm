# frozen_string_literal: true

module SwarmSDK
  module Permissions
    # Config parses and validates permission configuration for tools
    #
    # Handles:
    # - Allowed path patterns (allowlist)
    # - Denied path patterns (explicit denylist)
    # - Allowed command patterns (regex for Bash tool)
    # - Denied command patterns (regex for Bash tool)
    # - Relative paths converted to absolute based on agent directory
    # - Glob pattern matching with absolute paths
    #
    # All paths and patterns are converted to absolute:
    # - Patterns starting with / are kept as-is
    # - Relative patterns are expanded against the agent's base directory
    # - Paths starting with / are kept as-is
    # - Relative paths are expanded against the agent's base directory
    #
    # Example:
    #   config = Config.new(
    #     {
    #       allowed_paths: ["tmp/**/*"],
    #       denied_paths: ["tmp/secrets/**"],
    #       allowed_commands: ["^git (status|diff|log)$"],
    #       denied_commands: ["^rm -rf"]
    #     },
    #     base_directories: ["/home/user/project"]
    #   )
    #   config.allowed?("tmp/file.txt")  # => true (checks /home/user/project/tmp/file.txt)
    #   config.allowed?("tmp/secrets/key.pem")  # => false (denied takes precedence)
    #   config.command_allowed?("git status")  # => true
    #   config.command_allowed?("rm -rf /")  # => false (denied takes precedence)
    class Config
      attr_reader :allowed_patterns, :denied_patterns, :allowed_commands, :denied_commands

      # Initialize permission configuration
      #
      # @param config_hash [Hash] Permission configuration with :allowed_paths, :denied_paths, :allowed_commands, :denied_commands
      # @param base_directory [String] Base directory for the agent
      def initialize(config_hash, base_directory:)
        # Use agent's directory as the base for path resolution
        @base_directory = File.expand_path(base_directory)

        # Expand all patterns to absolute paths
        @allowed_patterns = expand_patterns(config_hash[:allowed_paths] || [])
        @denied_patterns = expand_patterns(config_hash[:denied_paths] || [])

        # Parse command patterns (regex strings)
        @allowed_commands = compile_regex_patterns(config_hash[:allowed_commands] || [])
        @denied_commands = compile_regex_patterns(config_hash[:denied_commands] || [])
      end

      # Check if a path is allowed according to this configuration
      #
      # Rules:
      # 1. Denied patterns take precedence and always block
      # 2. If allowed_paths specified: must match at least one pattern (allowlist)
      # 3. If allowed_paths NOT specified: allow everything (except denied)
      # 4. All paths are converted to absolute for consistent matching
      # 5. For directories used as search bases (Glob/Grep), allow if any pattern would match inside
      #
      # @param path [String] Path to check (relative or absolute)
      # @param directory_search [Boolean] True if this is a directory search base (Glob/Grep)
      # @return [Boolean] True if path is allowed
      def allowed?(path, directory_search: false)
        # Convert path to absolute
        absolute_path = to_absolute_path(path)

        # Denied patterns take precedence - check first
        return false if matches_any?(@denied_patterns, absolute_path)

        # If no allowed patterns, allow everything (except denied)
        return true if @allowed_patterns.empty?

        # For directory searches, check if directory is a prefix of any allowed pattern
        # Don't check if directory exists - allow non-existent directories as search bases
        if directory_search
          return true if allowed_as_search_base?(absolute_path)
        end

        # Must match at least one allowed pattern
        matches_any?(@allowed_patterns, absolute_path)
      end

      # Find the specific pattern that denies or doesn't allow a path
      #
      # @param path [String] Path to check (relative or absolute)
      # @param directory_search [Boolean] True if this is a directory search base (Glob/Grep)
      # @return [String, nil] The pattern that blocks this path, or nil if allowed
      def find_blocking_pattern(path, directory_search: false)
        absolute_path = to_absolute_path(path)

        # Check denied patterns first
        denied_match = @denied_patterns.find { |pattern| PathMatcher.matches?(pattern, absolute_path) }
        return denied_match if denied_match

        # Check allowed patterns
        if @allowed_patterns.any?
          # For directory searches, check if allowed as search base
          # Don't check if directory exists - allow non-existent directories as search bases
          if directory_search
            return if allowed_as_search_base?(absolute_path)
          end

          # Check if path matches any allowed pattern
          return if @allowed_patterns.any? { |pattern| PathMatcher.matches?(pattern, absolute_path) }

          # Path doesn't match any allowed pattern
          return "(not in allowed list)"
        end

        nil
      end

      # Convert a path to absolute form
      #
      # @param path [String] Path to convert
      # @return [String] Absolute path
      def to_absolute(path)
        to_absolute_path(path)
      end

      # Check if a command is allowed according to this configuration
      #
      # Rules:
      # 1. Denied command patterns take precedence and always block
      # 2. If allowed_commands specified: must match at least one pattern (allowlist)
      # 3. If allowed_commands NOT specified: allow everything (except denied)
      #
      # @param command [String] Command to check
      # @return [Boolean] True if command is allowed
      def command_allowed?(command)
        # Denied patterns take precedence - check first
        return false if matches_any_regex?(@denied_commands, command)

        # If no allowed patterns, allow everything (except denied)
        return true if @allowed_commands.empty?

        # Must match at least one allowed pattern
        matches_any_regex?(@allowed_commands, command)
      end

      # Find the specific pattern that denies or doesn't allow a command
      #
      # @param command [String] Command to check
      # @return [String, nil] The pattern that blocks this command, or nil if allowed
      def find_blocking_command_pattern(command)
        # Check denied patterns first
        denied_match = @denied_commands.find { |pattern| pattern.match?(command) }
        return denied_match.source if denied_match

        # Check allowed patterns
        if @allowed_commands.any?
          # Check if command matches any allowed pattern
          return if @allowed_commands.any? { |pattern| pattern.match?(command) }

          # Command doesn't match any allowed pattern
          return "(not in allowed list)"
        end

        nil
      end

      private

      # Expand patterns to absolute paths
      #
      # Patterns starting with / are kept as-is
      # Relative patterns are joined with base directory
      def expand_patterns(patterns)
        Array(patterns).map do |pattern|
          if pattern.to_s.start_with?("/")
            pattern.to_s
          else
            File.join(@base_directory, pattern.to_s)
          end
        end
      end

      # Convert path to absolute
      #
      # Paths starting with / are kept as-is
      # Relative paths are expanded against base directory
      def to_absolute_path(path)
        if path.start_with?("/")
          path
        else
          File.expand_path(path, @base_directory)
        end
      end

      # Check if path matches any pattern in the list
      def matches_any?(patterns, path)
        patterns.any? { |pattern| PathMatcher.matches?(pattern, path) }
      end

      # Check if a directory is allowed as a search base
      #
      # A directory is allowed as a search base if any allowed pattern
      # would match files or directories inside it.
      #
      # @param directory_path [String] Absolute path to directory
      # @return [Boolean] True if directory can be used as search base
      def allowed_as_search_base?(directory_path)
        # Normalize directory path (ensure trailing slash for comparison)
        dir_with_slash = directory_path.end_with?("/") ? directory_path : "#{directory_path}/"

        @allowed_patterns.any? do |pattern|
          # Check if the pattern starts with this directory
          # This means files inside this directory would match the pattern
          pattern.start_with?(dir_with_slash) || pattern == directory_path
        end
      end

      # Compile regex patterns from strings
      #
      # @param patterns [Array<String>] Array of regex pattern strings
      # @return [Array<Regexp>] Array of compiled regex objects
      def compile_regex_patterns(patterns)
        Array(patterns).map do |pattern|
          Regexp.new(pattern)
        rescue RegexpError => e
          raise ConfigurationError, "Invalid regex pattern '#{pattern}': #{e.message}"
        end
      end

      # Check if command matches any regex pattern in the list
      #
      # @param patterns [Array<Regexp>] Array of compiled regex patterns
      # @param command [String] Command to check
      # @return [Boolean] True if command matches any pattern
      def matches_any_regex?(patterns, command)
        patterns.any? { |pattern| pattern.match?(command) }
      end
    end
  end
end
