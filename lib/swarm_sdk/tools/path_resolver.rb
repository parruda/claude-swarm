# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Shared path resolution logic for all file tools
    #
    # Tools resolve relative paths against the agent's directory.
    # Absolute paths are used as-is.
    #
    # @example
    #   class Read < RubyLLM::Tool
    #     include PathResolver
    #
    #     def initialize(agent_name:, directory:)
    #       @directory = File.expand_path(directory)
    #     end
    #
    #     def execute(file_path:)
    #       resolved_path = resolve_path(file_path)
    #       File.read(resolved_path)
    #     end
    #   end
    module PathResolver
      private

      # Resolve a path relative to the agent's directory
      #
      # - Absolute paths (starting with /) are returned as-is
      # - Relative paths are resolved against @directory
      #
      # @param path [String] Path to resolve (relative or absolute)
      # @return [String] Absolute path
      # @raise [RuntimeError] If @directory not set (developer error)
      def resolve_path(path)
        raise "PathResolver requires @directory to be set" unless @directory

        return path if path.to_s.start_with?("/")

        File.expand_path(path, @directory)
      end
    end
  end
end
