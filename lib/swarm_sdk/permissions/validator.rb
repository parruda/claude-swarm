# frozen_string_literal: true

module SwarmSDK
  module Permissions
    # Validator decorates tools to enforce permission checks before execution
    #
    # Uses the Decorator pattern (via SimpleDelegator) to wrap tool instances
    # and validate file paths and commands before allowing tool execution.
    #
    # Example:
    #   write_tool = Tools::Write.new
    #   permissions = Config.new(
    #     {
    #       allowed_paths: ["tmp/**/*"],
    #       allowed_commands: ["^git (status|diff)$"]
    #     },
    #     base_directories: ["."]
    #   )
    #   validated_tool = Validator.new(write_tool, permissions)
    #
    #   # This will be denied:
    #   validated_tool.call({"file_path" => "/etc/passwd", "content" => "..."})
    class Validator < SimpleDelegator
      # Initialize validator decorator
      #
      # @param tool [RubyLLM::Tool] Tool instance to wrap
      # @param permissions_config [Config] Permission configuration
      def initialize(tool, permissions_config)
        super(tool)
        @permissions = permissions_config
        @tool = tool
      end

      # Intercept RubyLLM's call method to validate permissions
      #
      # RubyLLM calls tool.call(args) where args have string keys.
      # We must override call (not execute) because SimpleDelegator doesn't
      # automatically intercept methods defined in the superclass.
      #
      # @param args [Hash] Tool arguments with string keys
      # @return [String] Tool result or permission denied message
      def call(args)
        # Validate Bash commands if this is the Bash tool
        if bash_tool?
          command = args["command"]
          if command && !@permissions.command_allowed?(command)
            # Find the specific pattern that blocks this command
            matching_pattern = @permissions.find_blocking_command_pattern(command)

            return ErrorFormatter.command_permission_denied(
              command: command,
              allowed_patterns: @permissions.allowed_commands,
              denied_patterns: @permissions.denied_commands,
              matching_pattern: matching_pattern,
              tool_name: @tool.name,
            )
          end
        end

        # Extract paths from arguments (handles both string and symbol keys)
        paths = extract_paths_from_args(args)

        # Determine if this is a directory search tool (Glob/Grep)
        directory_search = directory_search_tool?

        # Validate each path
        paths.each do |path|
          next if @permissions.allowed?(path, directory_search: directory_search)

          # Show absolute path in error message for clarity
          absolute_path = @permissions.to_absolute(path)

          # Find the specific pattern that blocks this path
          matching_pattern = @permissions.find_blocking_pattern(path, directory_search: directory_search)

          return ErrorFormatter.permission_denied(
            path: absolute_path,
            allowed_patterns: @permissions.allowed_patterns,
            denied_patterns: @permissions.denied_patterns,
            matching_pattern: matching_pattern,
            tool_name: @tool.name,
          )
        end

        # All permissions validated, call wrapped tool
        __getobj__.call(args)
      end

      private

      # Check if the tool is the Bash tool
      #
      # @return [Boolean] True if tool is Bash
      def bash_tool?
        @tool.name.to_s == "Bash"
      end

      # Check if the tool is a directory search tool (Glob or Grep)
      #
      # @return [Boolean] True if tool searches directories
      def directory_search_tool?
        tool_name = @tool.name.to_s
        tool_name == "Glob" || tool_name == "Grep"
      end

      # Extract file paths from tool arguments
      #
      # RubyLLM always passes arguments with string keys to call().
      #
      # Different tools have different parameter structures:
      # - Write/Edit/Read: file_path parameter
      # - MultiEdit: edits array with file_path in each edit
      # - Glob/Grep: path parameter (directory to search)
      # - Glob: pattern parameter may contain directory (e.g., "lib/**/*.rb")
      # - Bash: command parameter (validated separately via command_allowed?)
      #
      # @param args [Hash] Tool arguments with string keys
      # @return [Array<String>] List of file paths to validate
      def extract_paths_from_args(args)
        paths = []

        # Single file path parameter (Write, Edit, Read)
        paths << args["file_path"] if args["file_path"]

        # Path parameter (Glob, Grep)
        paths << args["path"] if args["path"]

        # Glob pattern may contain directory prefix (e.g., "lib/**/*.rb")
        # Extract the base directory from the pattern for validation
        # Note: Only do this for Glob, not Grep (Grep pattern is a regex, not a path)
        if @tool.name.to_s == "Glob"
          pattern = args["pattern"]
          if pattern && !pattern.start_with?("/")
            # Extract first directory component from relative patterns
            base_dir = extract_base_directory(pattern)
            paths << base_dir if base_dir
          end
        end

        # MultiEdit has array of edits
        edits = args["edits"]
        edits&.each do |edit|
          paths << edit["file_path"] if edit.is_a?(Hash) && edit["file_path"]
        end

        paths.compact.uniq
      end

      # Extract base directory from a glob pattern
      #
      # Examples:
      #   "lib/**/*.rb" => "lib"
      #   "src/main.rb" => "src"
      #   "**/*.rb" => nil (no specific directory)
      #   "*.rb" => nil (current directory)
      #
      # @param pattern [String] Glob pattern
      # @return [String, nil] Base directory or nil
      def extract_base_directory(pattern)
        return if pattern.nil? || pattern.empty?

        # Split on / and take first component
        parts = pattern.split("/")
        first_part = parts.first

        # Skip if pattern starts with wildcard (means current directory)
        return if first_part.include?("*") || first_part.include?("?")

        first_part
      end
    end
  end
end
