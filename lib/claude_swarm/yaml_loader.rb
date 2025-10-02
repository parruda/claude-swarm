# frozen_string_literal: true

module ClaudeSwarm
  # Provides consistent YAML loading across the application
  module YamlLoader
    class << self
      # Load a YAML configuration file (enables aliases for configuration flexibility)
      # @param file_path [String] Path to the configuration file
      # @return [Hash] The loaded configuration
      # @raise [ClaudeSwarm::Error] Re-raises with a more descriptive error message
      def load_config_file(file_path)
        YAML.load_file(file_path, aliases: true)
      rescue Errno::ENOENT
        raise ClaudeSwarm::Error, "Configuration file not found: #{file_path}"
      rescue Psych::SyntaxError => e
        raise ClaudeSwarm::Error, "Invalid YAML syntax in #{file_path}: #{e.message}"
      rescue Psych::BadAlias => e
        raise ClaudeSwarm::Error, "Invalid YAML alias in #{file_path}: #{e.message}"
      end
    end
  end
end
