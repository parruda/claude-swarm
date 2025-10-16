# frozen_string_literal: true

module SwarmSDK
  module Permissions
    # PathMatcher handles glob pattern matching for file paths
    #
    # Supports gitignore-style glob patterns with:
    # - Standard globs: *, **, ?, [abc], {a,b}
    # - Recursive matching: **/* matches all nested files
    # - Negation: !pattern to explicitly deny
    #
    # Examples:
    #   PathMatcher.matches?("tmp/**/*", "tmp/foo/bar.rb")  # => true
    #   PathMatcher.matches?("*.log", "debug.log")          # => true
    #   PathMatcher.matches?("src/**/*.{rb,js}", "src/a/b.rb")  # => true
    class PathMatcher
      class << self
        # Check if a path matches a glob pattern
        #
        # @param pattern [String] Glob pattern to match against
        # @param path [String] File path to check
        # @return [Boolean] True if path matches pattern
        def matches?(pattern, path)
          # Remove leading ! for negation patterns (handled by caller)
          pattern = pattern.delete_prefix("!")

          # Use File.fnmatch with pathname and extglob flags
          # FNM_PATHNAME: ** matches directories recursively
          # FNM_EXTGLOB: Support {a,b} patterns
          File.fnmatch(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        end
      end
    end
  end
end
