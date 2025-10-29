# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for searching memory entries by glob pattern
    #
    # Finds memory entries matching a glob pattern (like filesystem glob).
    # Each agent has its own isolated memory storage.
    class MemoryGlob < RubyLLM::Tool
      description <<~DESC
        Search your memory entries using glob patterns (like filesystem glob).

        REQUIRED: Provide the pattern parameter - the glob pattern to match entries against.

        **Parameters:**
        - pattern (REQUIRED): Glob pattern with wildcards (e.g., '**/*.txt', 'parallel/*/task_*', 'skill/**')

        **Glob Pattern Syntax (Standard Ruby Glob):**
        - `*` - matches .md files at a single directory level (e.g., 'fact/*' → fact/*.md)
        - `**` - matches .md files recursively at any depth (e.g., 'fact/**' → fact/**/*.md)
        - `?` - matches any single character (e.g., 'task_?')
        - `[abc]` - matches any character in the set (e.g., 'task_[0-9]')

        **Returns:**
        List of matching .md memory entries with:
        - Full memory:// path
        - Entry title
        - Size in bytes/KB/MB

        **Note**: Only returns .md files (actual memory entries), not directory entries.

        **MEMORY STRUCTURE (4 Fixed Categories Only):**
        ALL patterns MUST target one of these 4 categories:
        - concept/{domain}/** - Abstract ideas
        - fact/{subfolder}/** - Concrete information
        - skill/{domain}/** - Procedures
        - experience/** - Lessons
        INVALID: documentation/, reference/, parallel/, analysis/, tutorial/

        **Common Use Cases:**
        ```
        # Find direct .md files in fact/
        MemoryGlob(pattern: "fact/*")
        Result: fact/api.md (only direct children, not nested)

        # Find ALL facts recursively
        MemoryGlob(pattern: "fact/**")
        Result: fact/api.md, fact/people/john.md, fact/people/jane.md, ...

        # Find all skills recursively
        MemoryGlob(pattern: "skill/**")
        Result: skill/debugging/api-errors.md, skill/meta/deep-learning.md, ...

        # Find all concepts in a domain
        MemoryGlob(pattern: "concept/ruby/**")
        Result: concept/ruby/classes.md, concept/ruby/modules.md, ...

        # Find direct files in fact/people/
        MemoryGlob(pattern: "fact/people/*")
        Result: fact/people/john.md, fact/people/jane.md (not fact/people/teams/x.md)

        # Find all experiences
        MemoryGlob(pattern: "experience/**")
        Result: experience/fixed-cors-bug.md, experience/optimization.md, ...

        # Find debugging skills recursively
        MemoryGlob(pattern: "skill/debugging/**")
        Result: skill/debugging/api-errors.md, skill/debugging/performance.md, ...

        # Find all entries (all categories)
        MemoryGlob(pattern: "**/*")
        Result: All .md entries across all 4 categories
        ```

        **Understanding * vs **:**
        - `fact/*` matches only direct .md files: fact/api.md
        - `fact/**` matches ALL .md files recursively: fact/api.md, fact/people/john.md, ...
        - To explore subdirectories, use recursive pattern and examine returned paths

        **When to Use MemoryGlob:**
        - Discovering what's in a memory hierarchy
        - Finding all entries matching a naming convention
        - Locating related entries by path pattern
        - Exploring memory structure before reading specific entries
        - Batch operations preparation (find all, then process each)

        **Combining with Other Tools:**
        1. Use MemoryGlob to find candidates
        2. Use MemoryRead to examine specific entries
        3. Use MemoryEdit/MemoryDelete to modify/remove them

        **Tips:**
        - Start with broad patterns and narrow down
        - Use `**` for recursive searching entire hierarchies
        - Combine with MemoryGrep if you need content-based search
        - Check entry sizes to identify large entries
      DESC

      param :pattern,
        desc: "Glob pattern - target concept/, fact/, skill/, or experience/ only (e.g., 'skill/**', 'concept/ruby/*', 'fact/people/*.md')",
        required: true

      MAX_RESULTS = 500 # Limit results to prevent overwhelming output

      # Initialize with storage instance
      #
      # @param storage [Core::Storage] Storage instance
      def initialize(storage:)
        super()
        @storage = storage
      end

      # Override name to return simple "MemoryGlob"
      def name
        "MemoryGlob"
      end

      # Execute the tool
      #
      # @param pattern [String] Glob pattern to match
      # @return [String] Formatted list of matching entries
      def execute(pattern:)
        entries = @storage.glob(pattern: pattern)

        if entries.empty?
          return "No entries found matching pattern '#{pattern}'"
        end

        # Limit results
        if entries.count > MAX_RESULTS
          entries = entries.take(MAX_RESULTS)
          truncated = true
        else
          truncated = false
        end

        result = []
        result << "Memory entries matching '#{pattern}' (#{entries.size} #{entries.size == 1 ? "entry" : "entries"}):"

        entries.each do |entry|
          result << "  memory://#{entry[:path]} - \"#{entry[:title]}\" (#{format_bytes(entry[:size])})"
        end

        output = result.join("\n")

        # Add system reminder if truncated
        if truncated
          output += <<~REMINDER

            <system-reminder>
            Results limited to first #{MAX_RESULTS} matches (sorted by most recently modified).
            Consider using a more specific pattern to narrow your search.
            </system-reminder>
          REMINDER
        end

        output
      rescue ArgumentError => e
        validation_error(e.message)
      end

      private

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end

      # Format bytes to human-readable size
      #
      # @param bytes [Integer] Number of bytes
      # @return [String] Formatted size
      def format_bytes(bytes)
        if bytes >= 1_000_000
          "#{(bytes.to_f / 1_000_000).round(1)}MB"
        elsif bytes >= 1_000
          "#{(bytes.to_f / 1_000).round(1)}KB"
        else
          "#{bytes}B"
        end
      end
    end
  end
end
