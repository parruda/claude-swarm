# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for searching memory content by pattern
    #
    # Searches content stored in memory entries using regex patterns.
    # Each agent has its own isolated memory storage.
    class MemoryGrep < RubyLLM::Tool
      description <<~DESC
        Search your memory content using regular expression patterns (like grep).

        REQUIRED: Provide the pattern parameter - the regex pattern to search for in entry content.

        MEMORY STRUCTURE: Searches across all 4 fixed categories (concept/, fact/, skill/, experience/)
        NO OTHER top-level categories exist.

        **Required Parameters:**
        - pattern (REQUIRED): Regular expression pattern to search for (e.g., 'status: pending', 'TODO.*urgent', '\\btask_\\d+\\b')

        **Optional Parameters:**
        - path: Limit search to specific path (e.g., 'concept/', 'fact/api-design/', 'skill/ruby')
        - case_insensitive: Set to true for case-insensitive search (default: false)
        - output_mode: Choose output format - 'files_with_matches' (default), 'content', or 'count'

        **Output Modes Explained:**
        1. **files_with_matches** (default): Just shows which entries contain matches
           - Fast and efficient for discovery
           - Use when you want to know WHERE matches exist

        2. **content**: Shows matching lines with line numbers
           - See the actual matching content
           - Use when you need to read the matches in context

        3. **count**: Shows how many matches in each entry
           - Quantify occurrences
           - Use for statistics or finding entries with most matches

        **Regular Expression Syntax:**
        - Literal text: 'status: pending'
        - Any character: 'task.done'
        - Character classes: '[0-9]+' (digits), '[a-z]+' (lowercase)
        - Word boundaries: '\\btodo\\b' (exact word)
        - Anchors: '^Start' (line start), 'end$' (line end)
        - Quantifiers: '*' (0+), '+' (1+), '?' (0 or 1), '{3}' (exactly 3)
        - Alternation: 'pending|in-progress|blocked'

        **Path Parameter - Directory-Style Filtering:**
        The path parameter works just like searching in directories:
        - 'concept/' - Search only concept entries
        - 'fact/api-design' - Search only in fact/api-design (treats as directory)
        - 'fact/api-design/' - Same as above
        - 'skill/ruby/blocks.md' - Search only that specific file

        **Examples:**
        ```
        # Find entries containing "TODO" (case-sensitive)
        MemoryGrep(pattern: "TODO")

        # Search only in concepts
        MemoryGrep(pattern: "TODO", path: "concept/")

        # Search in a specific subdirectory
        MemoryGrep(pattern: "endpoint", path: "fact/api-design")

        # Search a specific file
        MemoryGrep(pattern: "lambda", path: "skill/ruby/blocks.md")

        # Find entries with any status (case-insensitive)
        MemoryGrep(pattern: "status:", case_insensitive: true)

        # Show actual content of matches in skills only
        MemoryGrep(pattern: "error|warning|failed", path: "skill/", output_mode: "content")

        # Count how many times "completed" appears in experiences
        MemoryGrep(pattern: "completed", path: "experience/", output_mode: "count")

        # Find task numbers in facts
        MemoryGrep(pattern: "task_\\d+", path: "fact/")

        # Find incomplete tasks
        MemoryGrep(pattern: "^- \\[ \\]", output_mode: "content")

        # Find entries mentioning specific functions
        MemoryGrep(pattern: "\\bprocess_data\\(")
        ```

        **Use Cases:**
        - Finding entries by keyword or phrase
        - Locating TODO items or action items
        - Searching for error messages or debugging info
        - Finding entries about specific code/functions
        - Identifying patterns in your memory
        - Content-based discovery (vs MemoryGlob's path-based discovery)

        **Combining with Other Tools:**
        1. Use MemoryGrep to find entries containing specific content
        2. Use MemoryRead to examine full entries
        3. Use MemoryEdit to update the found content

        **Tips:**
        - Start with simple literal patterns before using complex regex
        - Use case_insensitive=true for broader matches
        - Use path parameter to limit search scope (faster and more precise)
        - Use output_mode="content" to see context around matches
        - Escape special regex characters with backslash: \\. \\* \\? \\[ \\]
        - Test patterns on a small set before broad searches
        - Use word boundaries (\\b) for exact word matching
      DESC

      param :pattern,
        desc: "Regular expression pattern to search for",
        required: true

      param :path,
        desc: "Limit search to specific path (e.g., 'concept/', 'fact/api-design/', 'skill/ruby/blocks.md')",
        required: false

      param :case_insensitive,
        type: "boolean",
        desc: "Set to true for case-insensitive search (default: false)",
        required: false

      param :output_mode,
        desc: "Output mode: 'files_with_matches' (default), 'content', or 'count'",
        required: false

      # Initialize with storage instance
      #
      # @param storage [Core::Storage] Storage instance
      def initialize(storage:)
        super()
        @storage = storage
      end

      # Override name to return simple "MemoryGrep"
      def name
        "MemoryGrep"
      end

      # Execute the tool
      #
      # @param pattern [String] Regex pattern to search for
      # @param path [String, nil] Optional path filter
      # @param case_insensitive [Boolean] Whether to perform case-insensitive search
      # @param output_mode [String] Output mode
      # @return [String] Formatted search results
      def execute(pattern:, path: nil, case_insensitive: false, output_mode: "files_with_matches")
        results = @storage.grep(
          pattern: pattern,
          path: path,
          case_insensitive: case_insensitive,
          output_mode: output_mode,
        )

        format_results(results, pattern, output_mode, path)
      rescue ArgumentError => e
        validation_error(e.message)
      rescue RegexpError => e
        validation_error("Invalid regex pattern: #{e.message}")
      end

      private

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end

      def format_results(results, pattern, output_mode, path_filter)
        case output_mode
        when "files_with_matches"
          format_files_with_matches(results, pattern, path_filter)
        when "content"
          format_content(results, pattern, path_filter)
        when "count"
          format_count(results, pattern, path_filter)
        else
          validation_error("Invalid output_mode: #{output_mode}")
        end
      end

      def format_search_header(pattern, path_filter)
        if path_filter && !path_filter.empty?
          "'#{pattern}' in #{path_filter}"
        else
          "'#{pattern}'"
        end
      end

      def format_files_with_matches(paths, pattern, path_filter)
        search_desc = format_search_header(pattern, path_filter)

        if paths.empty?
          return "No matches found for pattern #{search_desc}"
        end

        result = []
        result << "Memory entries matching #{search_desc} (#{paths.size} #{paths.size == 1 ? "entry" : "entries"}):"
        paths.each do |path|
          result << "  memory://#{path}"
        end
        result.join("\n")
      end

      def format_content(results, pattern, path_filter)
        search_desc = format_search_header(pattern, path_filter)

        if results.empty?
          return "No matches found for pattern #{search_desc}"
        end

        total_matches = results.sum { |r| r[:matches].size }
        output = []
        output << "Memory entries matching #{search_desc} (#{results.size} #{results.size == 1 ? "entry" : "entries"}, #{total_matches} #{total_matches == 1 ? "match" : "matches"}):"
        output << ""

        results.each do |result|
          output << "memory://#{result[:path]}:"
          result[:matches].each do |match|
            output << "  #{match[:line_number]}: #{match[:content]}"
          end
          output << ""
        end

        output.join("\n").rstrip
      end

      def format_count(results, pattern, path_filter)
        search_desc = format_search_header(pattern, path_filter)

        if results.empty?
          return "No matches found for pattern #{search_desc}"
        end

        total_matches = results.sum { |r| r[:count] }
        output = []
        output << "Memory entries matching #{search_desc} (#{results.size} #{results.size == 1 ? "entry" : "entries"}, #{total_matches} total #{total_matches == 1 ? "match" : "matches"}):"

        results.each do |result|
          output << "  memory://#{result[:path]}: #{result[:count]} #{result[:count] == 1 ? "match" : "matches"}"
        end

        output.join("\n")
      end
    end
  end
end
