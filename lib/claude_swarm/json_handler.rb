# frozen_string_literal: true

module ClaudeSwarm
  # Centralized JSON handling for the Claude Swarm codebase
  class JsonHandler
    class << self
      # Parse JSON string into Ruby object
      # @param json_string [String] The JSON string to parse
      # @param raise_on_error [Boolean] Whether to raise exception on error (default: false)
      # @return [Object] The parsed Ruby object, or original string if parsing fails and raise_on_error is false
      # @raise [JSON::ParserError] If the JSON is invalid and raise_on_error is true
      def parse(json_string, raise_on_error: false)
        JSON.parse(json_string)
      rescue JSON::ParserError => e
        raise e if raise_on_error

        json_string
      end

      # Parse JSON string with exception raising
      # @param json_string [String] The JSON string to parse
      # @return [Object] The parsed Ruby object
      # @raise [JSON::ParserError] If the JSON is invalid
      def parse!(json_string)
        parse(json_string, raise_on_error: true)
      end

      # Parse JSON from a file with exception raising
      # @param file_path [String] Path to the JSON file
      # @return [Object] The parsed Ruby object
      # @raise [Errno::ENOENT] If the file does not exist
      # @raise [JSON::ParserError] If the file contains invalid JSON
      def parse_file!(file_path)
        content = File.read(file_path)
        parse!(content)
      end

      # Parse JSON from a file, returning nil on error
      # @param file_path [String] Path to the JSON file
      # @return [Object, nil] The parsed Ruby object or nil if file doesn't exist or contains invalid JSON
      def parse_file(file_path)
        parse_file!(file_path)
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      # Generate pretty-formatted JSON string
      # @param object [Object] The Ruby object to convert to JSON
      # @param raise_on_error [Boolean] Whether to raise exception on error (default: false)
      # @return [String, nil] The pretty-formatted JSON string, or nil if generation fails and raise_on_error is false
      # @raise [JSON::GeneratorError] If the object cannot be converted to JSON and raise_on_error is true
      def pretty_generate(object, raise_on_error: false)
        JSON.pretty_generate(object)
      rescue JSON::GeneratorError, JSON::NestingError => e
        raise e if raise_on_error

        nil
      end

      # Generate pretty-formatted JSON string with exception raising
      # @param object [Object] The Ruby object to convert to JSON
      # @return [String] The pretty-formatted JSON string
      # @raise [JSON::GeneratorError] If the object cannot be converted to JSON
      def pretty_generate!(object)
        pretty_generate(object, raise_on_error: true)
      end

      # Write Ruby object to a JSON file with pretty formatting
      # @param file_path [String] Path to the JSON file
      # @param object [Object] The Ruby object to write
      # @return [Boolean] True if successful, false if generation or write fails
      def write_file(file_path, object)
        json_string = pretty_generate!(object)
        File.write(file_path, json_string)
        true
      rescue JSON::GeneratorError, JSON::NestingError, SystemCallError
        false
      end

      # Write Ruby object to a JSON file with exception raising
      # @param file_path [String] Path to the JSON file
      # @param object [Object] The Ruby object to write
      # @raise [JSON::GeneratorError] If the object cannot be converted to JSON
      # @raise [SystemCallError] If the file cannot be written
      def write_file!(file_path, object)
        json_string = pretty_generate!(object)
        File.write(file_path, json_string)
      end
    end
  end
end
