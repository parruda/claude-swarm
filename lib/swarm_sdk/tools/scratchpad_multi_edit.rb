# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Tool for performing multiple edits to a scratchpad entry
    #
    # Applies multiple edit operations sequentially to a single scratchpad entry.
    # Each edit sees the result of all previous edits, allowing for
    # coordinated multi-step transformations.
    # All agents in the swarm share the same scratchpad.
    class ScratchpadMultiEdit < RubyLLM::Tool
      define_method(:name) { "ScratchpadMultiEdit" }

      description <<~DESC
        Performs multiple exact string replacements in a single scratchpad entry.
        Edits are applied sequentially, so later edits see the results of earlier ones.
        You must use ScratchpadRead on the entry before editing it.
        When editing text from ScratchpadRead output, ensure you preserve the exact indentation as it appears AFTER the line number prefix.
        The line number prefix format is: spaces + line number + tab. Everything after that tab is the actual content to match.
        Never include any part of the line number prefix in the old_string or new_string.
        Each edit will FAIL if old_string is not unique in the entry. Either provide a larger string with more surrounding context to make it unique or use replace_all to change every instance of old_string.
        Use replace_all for replacing and renaming strings across the entry.
      DESC

      param :file_path,
        desc: "Path to the scratchpad entry (e.g., 'analysis/report', 'parallel/batch1/task_0')",
        required: true

      param :edits_json,
        type: "string",
        desc: <<~DESC.chomp,
          JSON array of edit operations. Each edit must have:
          old_string (exact text to replace),
          new_string (replacement text),
          and optionally replace_all (boolean, default false).
          Example: [{"old_string":"foo","new_string":"bar","replace_all":false}]
        DESC
        required: true

      class << self
        # Create a ScratchpadMultiEdit tool for a specific scratchpad instance
        #
        # @param scratchpad [Stores::Scratchpad] Shared scratchpad instance
        # @param agent_name [Symbol, String] Agent identifier for tracking reads
        # @return [ScratchpadMultiEdit] Tool instance
        def create_for_scratchpad(scratchpad, agent_name)
          new(scratchpad, agent_name)
        end
      end

      # Initialize with scratchpad instance and agent name
      #
      # @param scratchpad [Stores::Scratchpad] Shared scratchpad instance
      # @param agent_name [Symbol, String] Agent identifier
      def initialize(scratchpad, agent_name)
        super() # Call RubyLLM::Tool's initialize
        @scratchpad = scratchpad
        @agent_name = agent_name.to_sym
      end

      # Execute the tool
      #
      # @param file_path [String] Path to scratchpad entry
      # @param edits_json [String] JSON array of edit operations
      # @return [String] Success message or error
      def execute(file_path:, edits_json:)
        # Validate inputs
        return validation_error("file_path is required") if file_path.nil? || file_path.to_s.strip.empty?

        # Parse JSON
        edits = begin
          JSON.parse(edits_json)
        rescue JSON::ParserError
          nil
        end

        return validation_error("Invalid JSON format. Please provide a valid JSON array of edit operations.") if edits.nil?

        return validation_error("edits must be an array") unless edits.is_a?(Array)
        return validation_error("edits array cannot be empty") if edits.empty?

        # Read current content (this will raise ArgumentError if entry doesn't exist)
        content = scratchpad.read(file_path: file_path)

        # Enforce read-before-edit
        unless Stores::ScratchpadReadTracker.entry_read?(@agent_name, file_path)
          return validation_error(
            "Cannot edit scratchpad entry without reading it first. " \
              "You must use ScratchpadRead on 'scratchpad://#{file_path}' before editing it. " \
              "This ensures you have the current content to match against.",
          )
        end

        # Validate edit operations
        validated_edits = []
        edits.each_with_index do |edit, index|
          unless edit.is_a?(Hash)
            return validation_error("Edit at index #{index} must be a hash/object with old_string and new_string")
          end

          # Convert string keys to symbols for consistency
          edit = edit.transform_keys(&:to_sym)

          unless edit[:old_string]
            return validation_error("Edit at index #{index} missing required field 'old_string'")
          end

          unless edit[:new_string]
            return validation_error("Edit at index #{index} missing required field 'new_string'")
          end

          # old_string and new_string must be different
          if edit[:old_string] == edit[:new_string]
            return validation_error("Edit at index #{index}: old_string and new_string must be different")
          end

          validated_edits << {
            old_string: edit[:old_string].to_s,
            new_string: edit[:new_string].to_s,
            replace_all: edit[:replace_all] == true,
            index: index,
          }
        end

        # Apply edits sequentially
        results = []
        current_content = content

        validated_edits.each do |edit|
          # Check if old_string exists in current content
          unless current_content.include?(edit[:old_string])
            return error_with_results(
              <<~ERROR.chomp,
                Edit #{edit[:index]}: old_string not found in scratchpad entry.
                Make sure it matches exactly, including all whitespace and indentation.
                Do not include line number prefixes from ScratchpadRead tool output.
                Note: This edit follows #{edit[:index]} previous edit(s) which may have changed the content.
              ERROR
              results,
            )
          end

          # Count occurrences
          occurrences = current_content.scan(edit[:old_string]).count

          # If not replace_all and multiple occurrences, error
          if !edit[:replace_all] && occurrences > 1
            return error_with_results(
              <<~ERROR.chomp,
                Edit #{edit[:index]}: Found #{occurrences} occurrences of old_string.
                Either provide more surrounding context to make the match unique, or set replace_all: true to replace all occurrences.
              ERROR
              results,
            )
          end

          # Perform replacement
          new_content = if edit[:replace_all]
            current_content.gsub(edit[:old_string], edit[:new_string])
          else
            current_content.sub(edit[:old_string], edit[:new_string])
          end

          # Record result
          replaced_count = edit[:replace_all] ? occurrences : 1
          results << {
            index: edit[:index],
            status: "success",
            occurrences: replaced_count,
            message: "Replaced #{replaced_count} occurrence(s)",
          }

          # Update content for next edit
          current_content = new_content
        end

        # Get existing entry metadata
        entries = scratchpad.list
        existing_entry = entries.find { |e| e[:path] == file_path }

        # Write updated content back (preserving the title)
        scratchpad.write(
          file_path: file_path,
          content: current_content,
          title: existing_entry[:title],
        )

        # Build success message
        total_replacements = results.sum { |r| r[:occurrences] }
        message = "Successfully applied #{validated_edits.size} edit(s) to scratchpad://#{file_path}\n"
        message += "Total replacements: #{total_replacements}\n\n"
        message += "Details:\n"
        results.each do |result|
          message += "  Edit #{result[:index]}: #{result[:message]}\n"
        end

        message
      rescue ArgumentError => e
        validation_error(e.message)
      end

      private

      attr_reader :scratchpad

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end

      def error_with_results(message, results)
        output = "<tool_use_error>InputValidationError: #{message}\n\n"

        if results.any?
          output += "Previous successful edits before error:\n"
          results.each do |result|
            output += "  Edit #{result[:index]}: #{result[:message]}\n"
          end
          output += "\n"
        end

        output += "Note: The scratchpad entry has NOT been modified. All or nothing approach - if any edit fails, no changes are saved.</tool_use_error>"
        output
      end
    end
  end
end
