# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Permissions
    class PermissionsTest < Minitest::Test
      def setup
        @base_dir = File.expand_path(".")
      end

      # PathMatcher tests
      def test_path_matcher_matches_simple_pattern
        assert(PathMatcher.matches?("*.log", "debug.log"))
        refute(PathMatcher.matches?("*.log", "debug.txt"))
      end

      def test_path_matcher_matches_recursive_pattern
        assert(PathMatcher.matches?("tmp/**/*", "tmp/foo/bar.rb"))
        assert(PathMatcher.matches?("tmp/**/*", "tmp/file.txt"))
        refute(PathMatcher.matches?("tmp/**/*", "src/file.txt"))
      end

      def test_path_matcher_matches_extglob_pattern
        assert(PathMatcher.matches?("src/**/*.{rb,js}", "src/a/b.rb"))
        assert(PathMatcher.matches?("src/**/*.{rb,js}", "src/a/b.js"))
        refute(PathMatcher.matches?("src/**/*.{rb,js}", "src/a/b.py"))
      end

      def test_path_matcher_handles_negation_prefix
        # Negation prefix is stripped by PathMatcher (caller handles logic)
        assert(PathMatcher.matches?("!*.log", "debug.log"))
      end

      # Config tests
      def test_config_allows_matching_path
        config = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )

        assert(config.allowed?("tmp/file.txt"))
        assert(config.allowed?("tmp/subdir/file.txt"))
      end

      def test_config_denies_non_matching_path
        config = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )

        refute(config.allowed?("src/file.txt"))
        refute(config.allowed?("file.txt"))
      end

      def test_config_denied_paths_override_allowed
        config = Config.new(
          {
            allowed_paths: ["tmp/**/*"],
            denied_paths: ["tmp/secrets/**"],
          },
          base_directory: @base_dir,
        )

        assert(config.allowed?("tmp/file.txt"))
        refute(config.allowed?("tmp/secrets/key.pem"))
      end

      def test_config_handles_multiple_patterns
        config = Config.new(
          {
            allowed_paths: ["tmp/**/*", "logs/*.log", "output/**/*.json"],
          },
          base_directory: @base_dir,
        )

        assert(config.allowed?("tmp/file.txt"))
        assert(config.allowed?("logs/debug.log"))
        assert(config.allowed?("output/data/results.json"))
        refute(config.allowed?("src/file.rb"))
      end

      def test_config_handles_absolute_paths
        config = Config.new(
          { allowed_paths: ["/tmp/**/*"] },
          base_directory: @base_dir,
        )

        assert(config.allowed?("/tmp/file.txt"))
      end

      def test_config_with_only_denied_paths_allows_everything_else
        config = Config.new(
          { denied_paths: ["lib/**", ".env"] },
          base_directory: @base_dir,
        )

        # Should allow everything except denied paths
        assert(config.allowed?("tmp/file.txt"))
        assert(config.allowed?("src/file.rb"))
        assert(config.allowed?("README.md"))

        # Should deny the denied paths
        refute(config.allowed?("lib/foo.rb"))
        refute(config.allowed?(".env"))
      end

      def test_config_with_no_restrictions_allows_everything
        config = Config.new(
          {},
          base_directory: @base_dir,
        )

        # Should allow everything when no restrictions
        assert(config.allowed?("any/path/file.txt"))
        assert(config.allowed?("/etc/passwd"))
        assert(config.allowed?("lib/file.rb"))
      end

      def test_config_denied_paths_override_broader_allowed_paths
        config = Config.new(
          {
            allowed_paths: ["tmp/**/*"],
            denied_paths: ["tmp/LOL/**/*"],
          },
          base_directory: @base_dir,
        )

        # Should allow tmp/**/* except tmp/LOL/**/*
        assert(config.allowed?("tmp/file.txt"))
        assert(config.allowed?("tmp/subdir/file.txt"))
        refute(config.allowed?("tmp/LOL/file.txt"))
        refute(config.allowed?("tmp/LOL/nested/file.txt"))
      end

      def test_config_converts_relative_paths_to_absolute
        config = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )

        # Both relative and absolute forms of the same path should work
        assert(config.allowed?("tmp/file.txt"))
        assert(config.allowed?(File.join(@base_dir, "tmp/file.txt")))
      end

      def test_config_absolute_patterns_only_match_absolute_paths
        config = Config.new(
          { allowed_paths: ["/tmp/**/*"] },
          base_directory: @base_dir,
        )

        # Absolute pattern should match absolute path
        assert(config.allowed?("/tmp/file.txt"))

        # Should not match relative path even if it looks similar
        # (because relative "tmp/file.txt" becomes "/base_dir/tmp/file.txt")
        refute(config.allowed?("tmp/file.txt"))
      end

      # Validator tests
      def test_validator_allows_permitted_path
        tool = create_mock_write_tool
        permissions = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        result = validator.call("file_path" => "tmp/file.txt", "content" => "test")

        assert_equal("success", result)
      end

      def test_validator_denies_forbidden_path
        tool = create_mock_write_tool
        permissions = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        result = validator.call("file_path" => "/etc/passwd", "content" => "test")

        assert_includes(result, "Permission denied")
        assert_includes(result, "/etc/passwd")
        assert_includes(result, "tmp/**/*")
      end

      def test_validator_extracts_paths_from_multi_edit
        tool = create_mock_write_tool
        permissions = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        result = validator.call(
          "edits" => [
            { "file_path" => "tmp/file1.txt", "old_string" => "a", "new_string" => "b" },
            { "file_path" => "/etc/passwd", "old_string" => "a", "new_string" => "b" },
          ],
        )

        assert_includes(result, "Permission denied")
        assert_includes(result, "/etc/passwd")
      end

      def test_validator_validates_glob_path_parameter
        tool = create_mock_glob_tool
        permissions = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        # Allow path in tmp/
        result = validator.call("pattern" => "*.txt", "path" => "tmp")

        assert_equal("success", result)

        # Deny path outside tmp/
        result = validator.call("pattern" => "*.txt", "path" => "lib")

        assert_includes(result, "Permission denied")
        assert_includes(result, File.expand_path("lib", @base_dir))
      end

      def test_validator_validates_grep_path_parameter
        tool = create_mock_grep_tool
        permissions = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        # Allow path in tmp/
        result = validator.call("pattern" => "test", "path" => "tmp")

        assert_equal("success", result)

        # Deny path outside tmp/
        result = validator.call("pattern" => "test", "path" => "lib")

        assert_includes(result, "Permission denied")
        assert_includes(result, File.expand_path("lib", @base_dir))
      end

      def test_validator_allows_glob_without_path_parameter
        tool = create_mock_glob_tool
        permissions = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        # When path is nil, glob defaults to current directory
        # This should be allowed if no restrictions or if current dir is allowed
        result = validator.call("pattern" => "*.txt")

        assert_equal("success", result)
      end

      def test_validator_extracts_directory_from_glob_pattern
        tool = create_mock_glob_tool
        permissions = Config.new(
          { allowed_paths: ["test/**/*"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        # Pattern "lib/**/*.rb" should extract "lib" directory for validation
        result = validator.call("pattern" => "lib/**/*.rb")

        assert_includes(result, "Permission denied")
        assert_includes(result, File.expand_path("lib", @base_dir))
      end

      def test_validator_allows_glob_pattern_with_allowed_directory
        tool = create_mock_glob_tool
        permissions = Config.new(
          { allowed_paths: ["test/**/*"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        # Pattern "test/**/*.rb" should be allowed
        result = validator.call("pattern" => "test/**/*.rb")

        assert_equal("success", result)
      end

      def test_validator_ignores_wildcard_only_patterns
        tool = create_mock_glob_tool
        permissions = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        # Pattern "**/*.rb" has no specific directory, so it's allowed
        # (searches current directory which may or may not be restricted)
        result = validator.call("pattern" => "**/*.rb")

        assert_equal("success", result)
      end

      def test_validator_with_nil_path_parameter_in_glob
        tool = create_mock_glob_tool
        permissions = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        # When path is nil for Glob, should allow
        result = validator.call("pattern" => "*.txt", "path" => nil)

        assert_equal("success", result)
      end

      # Error formatter tests
      def test_error_formatter_generates_helpful_message
        message = ErrorFormatter.permission_denied(
          path: "/etc/passwd",
          allowed_patterns: ["tmp/**/*", "logs/*.log"],
          matching_pattern: "(not in allowed list)",
          tool_name: "Write",
        )

        assert_includes(message, "Permission denied")
        assert_includes(message, "/etc/passwd")
        assert_includes(message, "tmp/**/*")
        assert_includes(message, "logs/*.log")
        assert_includes(message, "<system-reminder>")
        assert_includes(message, "write to") # Operation verb instead of "Tool: Write"
      end

      def test_error_formatter_tool_name_read
        message = ErrorFormatter.permission_denied(
          path: "/etc/passwd",
          allowed_patterns: [],
          tool_name: "Read",
        )

        assert_includes(message, "read")
        refute_includes(message, "write")
      end

      def test_error_formatter_tool_name_edit
        message = ErrorFormatter.permission_denied(
          path: "/etc/passwd",
          allowed_patterns: [],
          tool_name: "Edit",
        )

        assert_includes(message, "edit")
      end

      def test_error_formatter_tool_name_multi_edit
        message = ErrorFormatter.permission_denied(
          path: "/etc/passwd",
          allowed_patterns: [],
          tool_name: "MultiEdit",
        )

        assert_includes(message, "edit")
      end

      def test_error_formatter_tool_name_glob
        message = ErrorFormatter.permission_denied(
          path: "/tmp",
          allowed_patterns: [],
          tool_name: "Glob",
        )

        assert_includes(message, "access directory")
      end

      def test_error_formatter_tool_name_grep
        message = ErrorFormatter.permission_denied(
          path: "/tmp",
          allowed_patterns: [],
          tool_name: "Grep",
        )

        assert_includes(message, "search in")
      end

      def test_error_formatter_tool_name_unknown
        message = ErrorFormatter.permission_denied(
          path: "/tmp",
          allowed_patterns: [],
          tool_name: "UnknownTool",
        )

        assert_includes(message, "access")
      end

      def test_error_formatter_with_specific_denied_pattern
        message = ErrorFormatter.permission_denied(
          path: "/tmp/secret.txt",
          allowed_patterns: ["tmp/**/*"],
          denied_patterns: ["tmp/secret*"],
          matching_pattern: "tmp/secret*",
          tool_name: "Read",
        )

        assert_includes(message, "Blocked by policy: tmp/secret*")
        refute_includes(message, "not in allowed list")
      end

      def test_error_formatter_with_denied_patterns_only
        message = ErrorFormatter.permission_denied(
          path: "/lib/secret.rb",
          allowed_patterns: [],
          denied_patterns: ["lib/**/*", "src/**/*"],
          tool_name: "Read",
        )

        assert_includes(message, "Denied paths:")
        assert_includes(message, "lib/**/*")
        assert_includes(message, "src/**/*")
      end

      def test_error_formatter_with_allowed_patterns_not_matched
        message = ErrorFormatter.permission_denied(
          path: "/lib/file.rb",
          allowed_patterns: ["tmp/**/*", "logs/**/*"],
          denied_patterns: [],
          matching_pattern: nil,
          tool_name: "Read",
        )

        assert_includes(message, "Allowed paths (not matched):")
        assert_includes(message, "tmp/**/*")
        assert_includes(message, "logs/**/*")
      end

      def test_error_formatter_with_no_policy
        message = ErrorFormatter.permission_denied(
          path: "/etc/passwd",
          allowed_patterns: [],
          denied_patterns: [],
          matching_pattern: nil,
          tool_name: "Read",
        )

        assert_includes(message, "No access policy configured")
      end

      # Bash command permissions tests
      def test_config_command_allowed_with_allowed_patterns
        config = Config.new(
          { allowed_commands: ["^git (status|diff|log)$", "^npm test$"] },
          base_directory: @base_dir,
        )

        assert(config.command_allowed?("git status"))
        assert(config.command_allowed?("git diff"))
        assert(config.command_allowed?("npm test"))
        refute(config.command_allowed?("rm -rf /"))
        refute(config.command_allowed?("git push"))
      end

      def test_config_command_allowed_with_denied_patterns
        config = Config.new(
          {
            allowed_commands: ["^git .*"],
            denied_commands: ["^git push.*--force"],
          },
          base_directory: @base_dir,
        )

        assert(config.command_allowed?("git status"))
        assert(config.command_allowed?("git push"))
        refute(config.command_allowed?("git push --force"))
        refute(config.command_allowed?("git push origin main --force"))
      end

      def test_config_command_allowed_with_no_restrictions
        config = Config.new(
          {},
          base_directory: @base_dir,
        )

        # Should allow everything when no command restrictions
        assert(config.command_allowed?("any command"))
        assert(config.command_allowed?("rm -rf /"))
      end

      def test_config_command_allowed_denied_takes_precedence
        config = Config.new(
          {
            allowed_commands: ["^rm .*"],
            denied_commands: ["^rm -rf /"],
          },
          base_directory: @base_dir,
        )

        assert(config.command_allowed?("rm file.txt"))
        refute(config.command_allowed?("rm -rf /"))
      end

      def test_validator_allows_permitted_bash_command
        tool = create_mock_bash_tool
        permissions = Config.new(
          { allowed_commands: ["^git (status|diff)$"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        result = validator.call("command" => "git status")

        assert_equal("success", result)
      end

      def test_validator_denies_forbidden_bash_command
        tool = create_mock_bash_tool
        permissions = Config.new(
          { allowed_commands: ["^git (status|diff)$"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        result = validator.call("command" => "rm -rf /")

        assert_includes(result, "Permission denied")
        assert_includes(result, "rm -rf /")
        assert_includes(result, "git (status|diff)")
      end

      def test_validator_denies_command_matching_denied_pattern
        tool = create_mock_bash_tool
        permissions = Config.new(
          { denied_commands: ["^rm -rf"] },
          base_directory: @base_dir,
        )
        validator = Validator.new(tool, permissions)

        result = validator.call("command" => "rm -rf /tmp")

        assert_includes(result, "Permission denied")
        assert_includes(result, "rm -rf /tmp")
      end

      def test_error_formatter_generates_helpful_command_message
        message = ErrorFormatter.command_permission_denied(
          command: "rm -rf /",
          allowed_patterns: [/^git (status|diff)$/, /^npm test$/],
          matching_pattern: "(not in allowed list)",
          tool_name: "bash",
        )

        assert_includes(message, "Permission denied")
        assert_includes(message, "rm -rf /")
        assert_includes(message, "^git (status|diff)$")
        assert_includes(message, "^npm test$")
        assert_includes(message, "<system-reminder>")
      end

      def test_command_error_formatter_with_specific_denied_pattern
        message = ErrorFormatter.command_permission_denied(
          command: "rm -rf /tmp",
          allowed_patterns: [],
          denied_patterns: [/^rm -rf/],
          matching_pattern: "^rm -rf",
          tool_name: "bash",
        )

        assert_includes(message, "Blocked by policy: ^rm -rf")
        refute_includes(message, "not in allowed list")
      end

      def test_command_error_formatter_with_denied_patterns_only
        message = ErrorFormatter.command_permission_denied(
          command: "rm file.txt",
          allowed_patterns: [],
          denied_patterns: [/^rm /, /^rmdir /],
          tool_name: "bash",
        )

        assert_includes(message, "Denied command patterns:")
        assert_includes(message, "^rm ")
        assert_includes(message, "^rmdir ")
      end

      def test_command_error_formatter_with_allowed_patterns_not_matched
        message = ErrorFormatter.command_permission_denied(
          command: "npm run build",
          allowed_patterns: [/^git /, /^npm test$/],
          denied_patterns: [],
          matching_pattern: nil,
          tool_name: "bash",
        )

        assert_includes(message, "Allowed command patterns (not matched):")
        assert_includes(message, "^git ")
        assert_includes(message, "^npm test$")
      end

      def test_command_error_formatter_with_no_policy
        message = ErrorFormatter.command_permission_denied(
          command: "ls",
          allowed_patterns: [],
          denied_patterns: [],
          matching_pattern: nil,
          tool_name: "bash",
        )

        assert_includes(message, "No command policy configured")
      end

      def test_config_raises_error_for_invalid_regex
        assert_raises(ConfigurationError) do
          Config.new(
            { allowed_commands: ["^git (status", "^npm test$"] }, # Invalid regex (unclosed paren)
            base_directory: @base_dir,
          )
        end
      end

      def test_config_allowed_with_directory_search_prefix_match
        config = Config.new(
          { allowed_paths: ["tmp/subdir/**/*"] },
          base_directory: @base_dir,
        )

        # Directory "tmp" should be allowed as search base because patterns inside it are allowed
        assert(config.allowed?("tmp", directory_search: true))
      end

      def test_config_allowed_with_directory_search_exact_match
        config = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )

        # Directory "tmp" should be allowed
        assert(config.allowed?("tmp", directory_search: true))
      end

      def test_config_allowed_with_directory_search_not_allowed
        config = Config.new(
          { allowed_paths: ["other/**/*"] },
          base_directory: @base_dir,
        )

        # Directory "tmp" should NOT be allowed (no patterns match inside it)
        refute(config.allowed?("tmp", directory_search: true))
      end

      def test_config_allowed_with_directory_search_denied
        # Create tmp directory for test
        tmp_dir = File.join(@base_dir, "tmp")
        Dir.mkdir(tmp_dir) unless Dir.exist?(tmp_dir)

        config = Config.new(
          { allowed_paths: ["tmp/**/*"], denied_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )

        # Directory "tmp" won't be caught by denied check (it matches the pattern for search base)
        # But files inside would be denied. Let's test a file inside instead
        refute(config.allowed?("tmp/file.txt", directory_search: false))
      ensure
        Dir.rmdir(tmp_dir) if tmp_dir && Dir.exist?(tmp_dir) && Dir.empty?(tmp_dir)
      end

      def test_config_find_blocking_pattern_with_denied
        config = Config.new(
          { denied_paths: ["lib/**/*"] },
          base_directory: @base_dir,
        )

        pattern = config.find_blocking_pattern("lib/file.rb")

        # Should return the denied pattern
        assert_match(/lib/, pattern)
      end

      def test_config_find_blocking_pattern_not_in_allowed_list
        config = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )

        pattern = config.find_blocking_pattern("lib/file.rb")

        assert_equal("(not in allowed list)", pattern)
      end

      def test_config_find_blocking_pattern_with_directory_search_allowed
        config = Config.new(
          { allowed_paths: ["tmp/**/*"] },
          base_directory: @base_dir,
        )

        pattern = config.find_blocking_pattern("tmp", directory_search: true)

        # Should return nil (allowed as search base)
        assert_nil(pattern)
      end

      def test_config_find_blocking_command_pattern_with_denied
        config = Config.new(
          { denied_commands: ["^rm -rf"] },
          base_directory: @base_dir,
        )

        pattern = config.find_blocking_command_pattern("rm -rf /tmp")

        assert_equal("^rm -rf", pattern)
      end

      def test_config_find_blocking_command_pattern_not_in_allowed_list
        config = Config.new(
          { allowed_commands: ["^git .*"] },
          base_directory: @base_dir,
        )

        pattern = config.find_blocking_command_pattern("npm install")

        assert_equal("(not in allowed list)", pattern)
      end

      def test_config_find_blocking_command_pattern_allowed
        config = Config.new(
          { allowed_commands: ["^git .*"] },
          base_directory: @base_dir,
        )

        pattern = config.find_blocking_command_pattern("git status")

        assert_nil(pattern)
      end

      def test_config_to_absolute_public_method
        config = Config.new(
          {},
          base_directory: @base_dir,
        )

        # Test the public to_absolute method
        absolute = config.to_absolute("tmp/file.txt")

        assert_equal(File.expand_path("tmp/file.txt", @base_dir), absolute)
      end

      # Integration tests for default write permissions
      def test_agent_definition_injects_default_write_permissions
        # Write, Edit, MultiEdit without explicit permissions should get defaults
        agent_def = SwarmSDK::Agent::Definition.new(
          :test_agent,
          {
            description: "Test agent",
            directory: ".",
            tools: [:Read, :Write, :Edit, :MultiEdit],
          },
        )

        # Read should have no permissions
        read_tool = agent_def.tools.find { |t| t[:name] == :Read }

        assert_nil(read_tool[:permissions])

        # Write, Edit, MultiEdit should have default permissions
        [:Write, :Edit, :MultiEdit].each do |tool_name|
          tool = agent_def.tools.find { |t| t[:name] == tool_name }

          assert_equal({ allowed_paths: ["**/*"] }, tool[:permissions], "#{tool_name} should have default write permissions")
        end
      end

      def test_explicit_permissions_override_defaults
        # Explicitly setting permissions should override the defaults
        agent_def = SwarmSDK::Agent::Definition.new(
          :test_agent,
          {
            description: "Test agent",
            directory: ".",
            tools: [
              { Write: { allowed_paths: ["custom/**/*"] } },
            ],
          },
        )

        write_tool = agent_def.tools.find { |t| t[:name] == :Write }

        assert_equal({ allowed_paths: ["custom/**/*"] }, write_tool[:permissions], "Explicit permissions should override defaults")
      end

      def test_default_write_permissions_restrict_to_agent_directory
        # Create a temp directory structure for testing
        Dir.mktmpdir do |base_dir|
          agent_dir = File.join(base_dir, "agent_workspace")
          other_dir = File.join(base_dir, "other_workspace")
          Dir.mkdir(agent_dir)
          Dir.mkdir(other_dir)

          agent_def = SwarmSDK::Agent::Definition.new(
            :test_agent,
            {
              description: "Test agent",
              directory: agent_dir,
              tools: [:Write],
            },
          )

          # Get the permissions for Write tool
          write_tool = agent_def.tools.find { |t| t[:name] == :Write }
          permissions = SwarmSDK::Permissions::Config.new(
            write_tool[:permissions],
            base_directory: agent_def.directory,
          )

          # Should allow writes within agent directory
          assert(permissions.allowed?(File.join(agent_dir, "file.txt")))
          assert(permissions.allowed?(File.join(agent_dir, "subdir/file.txt")))

          # Should deny writes outside agent directory
          refute(permissions.allowed?(File.join(other_dir, "file.txt")))
          refute(permissions.allowed?(File.join(base_dir, "file.txt")))
        end
      end

      private

      # Create a mock tool that returns "success" when called
      def create_mock_write_tool
        tool = Object.new
        def tool.name
          "Write"
        end

        def tool.call(_args)
          "success"
        end
        tool
      end

      def create_mock_glob_tool
        tool = Object.new
        def tool.name
          "Glob"
        end

        def tool.call(_args)
          "success"
        end
        tool
      end

      def create_mock_grep_tool
        tool = Object.new
        def tool.name
          "Grep"
        end

        def tool.call(_args)
          "success"
        end
        tool
      end

      def create_mock_bash_tool
        tool = Object.new
        def tool.name
          "Bash"
        end

        def tool.call(_args)
          "success"
        end
        tool
      end
    end
  end
end
