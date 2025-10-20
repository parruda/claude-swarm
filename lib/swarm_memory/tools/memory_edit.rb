# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for editing memory entries with exact string replacement
    #
    # Performs exact string replacements in memory content.
    # Each agent has its own isolated memory storage.
    class MemoryEdit < RubyLLM::Tool
      description <<~DESC
        Performs exact string replacements in memory entries.
        Works like the Edit tool but operates on memory content instead of files.
        You must use MemoryRead on the entry before editing it.
        When editing text from MemoryRead output, ensure you preserve the exact indentation as it appears AFTER the line number prefix.
        The line number prefix format is: spaces + line number + tab. Everything after that tab is the actual content to match.
        Never include any part of the line number prefix in the old_string or new_string.
        The edit will FAIL if old_string is not unique in the entry. Either provide a larger string with more surrounding context to make it unique or use replace_all to change every instance of old_string.
        Use replace_all for replacing and renaming strings across the entry.
      DESC

      param :file_path,
        desc: "Path to the memory entry (e.g., 'analysis/report', 'parallel/batch1/task_0')",
        required: true

      param :old_string,
        desc: "The exact text to replace (must match exactly including whitespace)",
        required: true

      param :new_string,
        desc: "The text to replace it with (must be different from old_string)",
        required: true

      param :replace_all,
        desc: "Replace all occurrences of old_string (default false)",
        required: false

      # Initialize with storage instance and agent name
      #
      # @param storage [Core::Storage] Storage instance
      # @param agent_name [String, Symbol] Agent identifier
      def initialize(storage:, agent_name:)
        super()
        @storage = storage
        @agent_name = agent_name.to_sym
      end

      # Override name to return simple "MemoryEdit"
      def name
        "MemoryEdit"
      end

      # Execute the tool
      #
      # @param file_path [String] Path to memory entry
      # @param old_string [String] Text to replace
      # @param new_string [String] Replacement text
      # @param replace_all [Boolean] Replace all occurrences
      # @return [String] Success message or error
      def execute(file_path:, old_string:, new_string:, replace_all: false)
        # Validate inputs
        return validation_error("file_path is required") if file_path.nil? || file_path.to_s.strip.empty?
        return validation_error("old_string is required") if old_string.nil? || old_string.empty?
        return validation_error("new_string is required") if new_string.nil?

        # old_string and new_string must be different
        if old_string == new_string
          return validation_error("old_string and new_string must be different. They are currently identical.")
        end

        # Read current content (this will raise ArgumentError if entry doesn't exist)
        content = @storage.read(file_path: file_path)

        # Enforce read-before-edit
        unless Core::StorageReadTracker.entry_read?(@agent_name, file_path)
          return validation_error(
            "Cannot edit memory entry without reading it first. " \
              "You must use MemoryRead on 'memory://#{file_path}' before editing it. " \
              "This ensures you have the current content to match against.",
          )
        end

        # Check if old_string exists in content
        unless content.include?(old_string)
          return validation_error(<<~ERROR.chomp)
            old_string not found in memory entry. Make sure it matches exactly, including all whitespace and indentation.
            Do not include line number prefixes from MemoryRead tool output.
          ERROR
        end

        # Count occurrences
        occurrences = content.scan(old_string).count

        # If not replace_all and multiple occurrences, error
        if !replace_all && occurrences > 1
          return validation_error(<<~ERROR.chomp)
            Found #{occurrences} occurrences of old_string.
            Either provide more surrounding context to make the match unique, or use replace_all: true to replace all occurrences.
          ERROR
        end

        # Perform replacement
        new_content = if replace_all
          content.gsub(old_string, new_string)
        else
          content.sub(old_string, new_string)
        end

        # Get existing entry metadata
        entry = @storage.read_entry(file_path: file_path)

        # Write updated content back (preserving the title)
        @storage.write(
          file_path: file_path,
          content: new_content,
          title: entry.title,
        )

        # Build success message
        replaced_count = replace_all ? occurrences : 1
        "Successfully replaced #{replaced_count} occurrence(s) in memory://#{file_path}"
      rescue ArgumentError => e
        validation_error(e.message)
      end

      private

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end
    end
  end
end
