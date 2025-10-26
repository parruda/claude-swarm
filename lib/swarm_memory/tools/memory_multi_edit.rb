# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for performing multiple edits to a memory entry
    #
    # Applies multiple edit operations sequentially to a single memory entry.
    # Each edit sees the result of all previous edits, allowing for
    # coordinated multi-step transformations.
    # Each agent has its own isolated memory storage.
    class MemoryMultiEdit < RubyLLM::Tool
      description <<~DESC
        Perform multiple exact string replacements in a single memory entry (applies edits sequentially).

        REQUIRED: Provide BOTH parameters - file_path and edits_json.

        **Required Parameters:**
        - file_path (REQUIRED): Path to memory entry - MUST start with concept/, fact/, skill/, or experience/
        - edits_json (REQUIRED): JSON array of edit operations - each must have old_string, new_string, and optionally replace_all

        **MEMORY STRUCTURE (4 Fixed Categories Only):**
        - concept/{domain}/** - Abstract ideas
        - fact/{subfolder}/** - Concrete information
        - skill/{domain}/** - Procedures
        - experience/** - Lessons
        INVALID: documentation/, reference/, project/, code/, parallel/

        **JSON Format:**
        ```json
        [
          {"old_string": "text to find", "new_string": "replacement text", "replace_all": false},
          {"old_string": "another find", "new_string": "another replace", "replace_all": true}
        ]
        ```

        **CRITICAL - Before Using This Tool:**
        1. You MUST use MemoryRead on the entry first - edits without reading will FAIL
        2. Copy text exactly from MemoryRead output, EXCLUDING the line number prefix
        3. Line number format: "    123→actual content" - only use text AFTER the arrow
        4. Edits are applied SEQUENTIALLY - later edits see results of earlier edits
        5. If ANY edit fails, NO changes are saved (all-or-nothing)

        **How Sequential Edits Work:**
        ```
        Original: "status: pending, priority: low"

        Edit 1: "pending" → "in-progress"
        Result: "status: in-progress, priority: low"

        Edit 2: "low" → "high"  (sees Edit 1's result)
        Final: "status: in-progress, priority: high"
        ```

        **Use Cases:**
        - Making multiple coordinated changes in one operation
        - Updating several related fields at once
        - Chaining transformations where order matters
        - Bulk find-and-replace operations

        **Examples:**
        ```
        # Update multiple fields in an experience
        MemoryMultiEdit(
          file_path: "experience/api-debugging.md",
          edits_json: '[
            {"old_string": "status: in-progress", "new_string": "status: resolved"},
            {"old_string": "confidence: medium", "new_string": "confidence: high"}
          ]'
        )

        # Rename function and update calls in a concept
        MemoryMultiEdit(
          file_path: "concept/ruby/functions.md",
          edits_json: '[
            {"old_string": "def old_func_name", "new_string": "def new_func_name"},
            {"old_string": "old_func_name()", "new_string": "new_func_name()", "replace_all": true}
          ]'
        )
        ```

        **Important Notes:**
        - All edits in the array must be valid JSON objects
        - Each old_string must be different from its new_string
        - Each old_string must be unique in content UNLESS replace_all is true
        - Failed edit shows which previous edits succeeded
        - More efficient than multiple MemoryEdit calls
      DESC

      param :file_path,
        desc: "Path to memory entry - MUST start with concept/, fact/, skill/, or experience/ (e.g., 'experience/api-debugging.md', 'concept/ruby/functions.md')",
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

      # Initialize with storage instance and agent name
      #
      # @param storage [Core::Storage] Storage instance
      # @param agent_name [String, Symbol] Agent identifier
      def initialize(storage:, agent_name:)
        super()
        @storage = storage
        @agent_name = agent_name.to_sym
      end

      # Override name to return simple "MemoryMultiEdit"
      def name
        "MemoryMultiEdit"
      end

      # Execute the tool
      #
      # @param file_path [String] Path to memory entry
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
        content = @storage.read(file_path: file_path)

        # Enforce read-before-edit
        unless Core::StorageReadTracker.entry_read?(@agent_name, file_path)
          return validation_error(
            "Cannot edit memory entry without reading it first. " \
              "You must use MemoryRead on 'memory://#{file_path}' before editing it. " \
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
                Edit #{edit[:index]}: old_string not found in memory entry.
                Make sure it matches exactly, including all whitespace and indentation.
                Do not include line number prefixes from MemoryRead tool output.
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

        # Get existing entry
        entry = @storage.read_entry(file_path: file_path)

        # Write updated content back (preserving the title)
        @storage.write(
          file_path: file_path,
          content: current_content,
          title: entry.title,
        )

        # Build success message
        total_replacements = results.sum { |r| r[:occurrences] }
        message = "Successfully applied #{validated_edits.size} edit(s) to memory://#{file_path}\n"
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

        output += "Note: The memory entry has NOT been modified. All or nothing approach - if any edit fails, no changes are saved.</tool_use_error>"
        output
      end
    end
  end
end
