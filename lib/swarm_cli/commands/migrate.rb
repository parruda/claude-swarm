# frozen_string_literal: true

module SwarmCLI
  module Commands
    # Migrate command converts Claude Swarm v1 configurations to SwarmSDK v2 format.
    #
    # Usage:
    #   swarm migrate old-config.yml
    #   swarm migrate old-config.yml --output new-config.yml
    #
    class Migrate
      attr_reader :options

      def initialize(options)
        @options = options
      end

      def execute
        # Validate options
        options.validate!

        # Create migrator
        migrator = Migrator.new(options.input_file)

        # Perform migration
        migrated_yaml = migrator.migrate

        # Write to output file or stdout
        if options.output
          File.write(options.output, migrated_yaml)
          $stderr.puts "✓ Migration complete! Converted configuration saved to: #{options.output}"
        else
          puts migrated_yaml
        end

        exit(0)
      rescue SwarmCLI::ExecutionError => e
        handle_error(e)
        exit(1)
      rescue Interrupt
        $stderr.puts "\n\nMigration cancelled by user"
        exit(130)
      rescue StandardError => e
        handle_error(e)
        exit(1)
      end

      private

      def handle_error(error)
        $stderr.puts "Error: #{error.message}"
      end
    end
  end
end
