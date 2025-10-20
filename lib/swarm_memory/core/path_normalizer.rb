# frozen_string_literal: true

module SwarmMemory
  module Core
    # Validates and normalizes memory paths
    #
    # Ensures paths are safe, hierarchical, and follow conventions.
    class PathNormalizer
      # Invalid path patterns
      INVALID_PATTERNS = [
        %r{\A/}, # Absolute paths
        /\.\./,          # Parent directory references
        %r{//},          # Double slashes
        /\A\s/,          # Leading whitespace
        /\s\z/,          # Trailing whitespace
        /[<>:"|?*]/,     # Invalid filesystem characters
      ].freeze

      class << self
        # Normalize and validate a memory path
        #
        # @param path [String] Path to normalize
        # @return [String] Normalized path
        # @raise [ArgumentError] If path is invalid
        #
        # @example
        #   PathNormalizer.normalize("concepts/ruby/classes.md")
        #   # => "concepts/ruby/classes.md"
        #
        #   PathNormalizer.normalize("../secrets")
        #   # => ArgumentError: Path cannot contain '..'
        def normalize(path)
          raise ArgumentError, "path is required" if path.nil? || path.to_s.strip.empty?

          original_path = path.to_s.strip

          # Check for absolute paths and parent references FIRST (before normalization)
          if original_path.start_with?("/")
            raise ArgumentError, "Invalid path: #{original_path}. Paths must be relative, hierarchical, and safe."
          end

          if original_path.include?("..")
            raise ArgumentError, "Invalid path: #{original_path}. Paths must be relative, hierarchical, and safe."
          end

          # Normalize (remove leading/trailing slashes, collapse doubles)
          path = original_path
          path = path.sub(%r{\A/+}, "")  # Remove leading slashes
          path = path.sub(%r{/+\z}, "")  # Remove trailing slashes
          path = path.gsub(%r{/+}, "/")  # Collapse multiple slashes

          # Check for other invalid characters
          if path.match?(/[<>:"|?*]/)
            raise ArgumentError, "Invalid path: #{original_path}. Paths must be relative, hierarchical, and safe."
          end

          raise ArgumentError, "Normalized path is empty" if path.empty?

          path
        end

        # Check if a path is valid without raising an exception
        #
        # @param path [String] Path to validate
        # @return [Boolean] True if path is valid
        def valid?(path)
          normalize(path)
          true
        rescue ArgumentError
          false
        end
      end
    end
  end
end
