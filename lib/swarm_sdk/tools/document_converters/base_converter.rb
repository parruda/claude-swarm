# frozen_string_literal: true

module SwarmSDK
  module Tools
    module DocumentConverters
      # Base class for document converters
      # Provides common interface and utility methods for converting various document formats
      class BaseConverter
        class << self
          # The gem name required for this converter
          # @return [String]
          def gem_name
            raise NotImplementedError, "#{name} must implement .gem_name"
          end

          # Human-readable format name
          # @return [String]
          def format_name
            raise NotImplementedError, "#{name} must implement .format_name"
          end

          # File extensions this converter handles
          # @return [Array<String>]
          def extensions
            raise NotImplementedError, "#{name} must implement .extensions"
          end

          # Check if the required gem is available
          # @return [Boolean]
          def available?
            gem_available?(gem_name)
          end

          # Check if a gem is installed
          # @param gem_name [String] Name of the gem to check
          # @return [Boolean]
          def gem_available?(gem_name)
            Gem::Specification.find_by_name(gem_name)
            true
          rescue Gem::LoadError
            false
          end
        end

        # Convert a document file to text/content
        # @param file_path [String] Path to the file
        # @return [String, RubyLLM::Content] Converted content or error message
        def convert(file_path)
          raise NotImplementedError, "#{self.class.name} must implement #convert"
        end

        protected

        # Return a system reminder about missing gem
        # @param format [String] Format name (e.g., "PDF")
        # @param gem_name [String] Required gem name
        # @return [String]
        def unsupported_format_reminder(format, gem_name)
          <<~REMINDER
            <system-reminder>
            This file is a #{format} document, but the required gem is not installed.

            To enable #{format} file reading, please install the gem:
              gem install #{gem_name}

            Or add to your Gemfile:
              gem "#{gem_name}"

            Don't install the gem yourself. Ask the user if they would like you to install this gem.
            </system-reminder>
          REMINDER
        end

        # Return an error message
        # @param message [String] Error message
        # @return [String]
        def error(message)
          "Error: #{message}"
        end
      end
    end
  end
end
