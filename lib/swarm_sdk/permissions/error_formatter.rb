# frozen_string_literal: true

module SwarmSDK
  module Permissions
    # ErrorFormatter generates user-friendly error messages for permission violations
    class ErrorFormatter
      class << self
        # Generate a permission denied error message
        #
        # @param path [String] The path that was denied
        # @param allowed_patterns [Array<String>] List of allowed path patterns
        # @param denied_patterns [Array<String>] List of denied path patterns
        # @param matching_pattern [String, nil] The specific pattern that blocked this path
        # @param tool_name [String] Name of the tool that was denied
        # @return [String] Formatted error message with system reminder
        def permission_denied(path:, allowed_patterns:, denied_patterns: [], matching_pattern: nil, tool_name:)
          operation_verb = case tool_name.to_s
          when "Read" then "read"
          when "Write" then "write to"
          when "Edit", "MultiEdit" then "edit"
          when "Glob" then "access directory"
          when "Grep" then "search in"
          else "access"
          end

          # Build policy explanation
          policy_info = if matching_pattern && matching_pattern != "(not in allowed list)"
            # Show the specific denied pattern that blocked this path
            "Blocked by policy: #{matching_pattern}"
          elsif matching_pattern == "(not in allowed list)" && allowed_patterns.any?
            # Show allowed patterns when path doesn't match any
            patterns = allowed_patterns.map { |p| "  - #{p}" }.join("\n")
            "Path not in allowed list. Allowed paths:\n#{patterns}"
          elsif denied_patterns.any?
            # Show denied patterns
            patterns = denied_patterns.map { |p| "  - #{p}" }.join("\n")
            "Denied paths:\n#{patterns}"
          elsif allowed_patterns.any?
            # Show allowed patterns
            patterns = allowed_patterns.map { |p| "  - #{p}" }.join("\n")
            "Allowed paths (not matched):\n#{patterns}"
          else
            "No access policy configured"
          end

          reminder = <<~REMINDER

            <system-reminder>
            PERMISSION DENIED: You do not have permission to #{operation_verb} '#{path}'.

            #{policy_info}

            This is an UNRECOVERABLE error set by user policy. You MUST stop trying to access files matching this pattern.

            Policy explanation:
            - This policy blocks ALL files matching the pattern, not just this specific file
            - Do not attempt to access other files matching this pattern - they will also be denied
            - Do not try to work around this restriction by using different tool arguments
            - The user has explicitly denied access to these resources via security policy

            You should inform the user that you cannot proceed due to permission restrictions on this file pattern.
            </system-reminder>
          REMINDER

          "Permission denied: Cannot #{operation_verb} '#{path}'#{reminder}"
        end

        # Generate a command permission denied error message
        #
        # @param command [String] The command that was denied
        # @param allowed_patterns [Array<Regexp>] List of allowed command regex patterns
        # @param denied_patterns [Array<Regexp>] List of denied command regex patterns
        # @param matching_pattern [String, nil] The specific pattern that blocked this command
        # @param tool_name [String] Name of the tool (typically "bash")
        # @return [String] Formatted error message with system reminder
        def command_permission_denied(command:, allowed_patterns:, denied_patterns: [], matching_pattern: nil, tool_name:)
          # Build policy explanation
          policy_info = if matching_pattern && matching_pattern != "(not in allowed list)"
            # Show the specific denied pattern that blocked this command
            "Blocked by policy: #{matching_pattern}"
          elsif matching_pattern == "(not in allowed list)" && allowed_patterns.any?
            # Show allowed patterns when command doesn't match any
            patterns = allowed_patterns.map { |p| "  - #{p.source}" }.join("\n")
            "Command not in allowed list. Allowed command patterns:\n#{patterns}"
          elsif denied_patterns.any?
            # Show denied patterns
            patterns = denied_patterns.map { |p| "  - #{p.source}" }.join("\n")
            "Denied command patterns:\n#{patterns}"
          elsif allowed_patterns.any?
            # Show allowed patterns
            patterns = allowed_patterns.map { |p| "  - #{p.source}" }.join("\n")
            "Allowed command patterns (not matched):\n#{patterns}"
          else
            "No command policy configured"
          end

          reminder = <<~REMINDER

            <system-reminder>
            PERMISSION DENIED: You do not have permission to execute command '#{command}'.

            #{policy_info}

            This is an UNRECOVERABLE error set by user policy. You MUST stop trying to execute commands matching this pattern.

            Policy explanation:
            - This policy blocks ALL commands matching the pattern, not just this specific command
            - Do not attempt to execute other commands matching this pattern - they will also be denied
            - Do not try to work around this restriction by modifying the command slightly
            - The user has explicitly denied access to these commands via security policy

            You should inform the user that you cannot proceed due to permission restrictions on this command.
            </system-reminder>
          REMINDER

          "Permission denied: Cannot execute command '#{command}'#{reminder}"
        end
      end
    end
  end
end
