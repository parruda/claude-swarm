# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for writing content to memory storage
    #
    # Stores content and metadata in persistent, per-agent memory storage.
    # Each agent has its own isolated memory storage that persists across sessions.
    class MemoryWrite < RubyLLM::Tool
      description <<~DESC
        Store content in persistent memory with structured metadata for semantic search and retrieval.

        IMPORTANT: Content must be 250 words or less. If content exceeds this limit, extract key entities: concepts, experiences, facts, skills,
        then split into multiple focused memories (each under 250 words) that capture ALL important details.
        Link related memories using the 'related' metadata field with memory:// URIs.

        CRITICAL: ALL 8 required parameters MUST be provided. Do NOT skip any. If you're missing information, ask the user or infer reasonable defaults.

        REQUIRED PARAMETERS (provide ALL 8):
        1. file_path - Where to store (e.g., 'concept/ruby/classes.md', 'skill/debugging/trace-errors.md')
        2. content - Pure markdown content (no frontmatter)
        3. title - Brief descriptive title
        4. type - Entry category: "concept", "fact", "skill", or "experience"
        5. confidence - How sure you are: "high", "medium", or "low"
        6. tags - JSON string of array of search keywords (e.g., '["ruby", "classes", "oop"]') - be comprehensive!
        7. related - JSON string of array of related memory paths (e.g., '["memory://concept/ruby/modules.md", "memory://concept/ruby/classes.md"]') or '[]' if none
        8. domain - Category like 'programming/ruby', 'people', 'debugging'
        9. source - Where this came from: "user", "documentation", "experimentation", or "inference"

        OPTIONAL (for skills only):
        - tools - JSON string of array of tool names needed (e.g., '["Read", "Edit", "Bash"]') or '[]' if none
        - permissions - Tool restrictions hash or {}

        PATH STRUCTURE (EXACTLY 4 TOP-LEVEL CATEGORIES - NEVER CREATE OTHERS):
        Memory has EXACTLY 4 fixed top-level categories. ALL paths MUST start with one of these:

        1. concept/{domain}/{name}.md - Abstract ideas (e.g., concept/ruby/classes.md)
        2. fact/{subfolder}/{name}.md - Concrete info (e.g., fact/people/john.md)
        3. skill/{domain}/{name}.md - How-to procedures (e.g., skill/debugging/api-errors.md)
        4. experience/{name}.md - Lessons learned (e.g., experience/fixed-cors-bug.md)

        INVALID (do NOT create): documentation/, reference/, tutorial/, knowledge/, notes/
        These categories do NOT exist. Use concept/, fact/, skill/, or experience/ instead.

        TAGS ARE CRITICAL: Think "What would I search for in 6 months?" For skills especially, be VERY comprehensive with tags - they're your search index.

        EXAMPLES:
        - For concept: tags: (JSON) "['ruby', 'oop', 'classes', 'inheritance', 'methods']"
        - For skill: tags: (JSON) "['debugging', 'api', 'http', 'errors', 'trace', 'network', 'rest']"
      DESC

      param :file_path,
        desc: "Path with .md extension (e.g., 'concept/ruby/classes.md', 'fact/people/john.md')",
        required: true

      param :content,
        desc: "Content to store (pure markdown, no frontmatter needed)",
        required: true

      param :title,
        desc: "Brief title describing the content",
        required: true

      # Metadata parameters (stored in .yml sidecar)
      param :type,
        desc: "Entry type: concept, fact, skill, or experience (matches category: concept/, fact/, skill/, experience/)",
        required: true

      param :confidence,
        desc: "Confidence level: high, medium, or low (defaults to 'medium' if not specified)",
        required: false

      param :tags,
        type: "string",
        desc: "JSON string of array of tag strings for searching (e.g., '[\"ruby\", \"oop\"]')",
        required: true

      param :related,
        type: "string",
        desc: "JSON string of array of related memory path strings (e.g., '[\"memory://concept/ruby/modules.md\", \"memory://concept/ruby/classes.md\"]')",
        required: true

      param :domain,
        desc: "Category/subcategory (e.g., 'programming/ruby', 'people')",
        required: true

      param :source,
        desc: "Source of information: user, documentation, experimentation, or inference (defaults to 'user' if not specified)",
        required: false

      param :tools,
        type: "string",
        desc: "JSON string of array of tool name strings required for this skill (e.g., '[\"Read\", \"Edit\", \"Bash\"]'). Only for type: skill",
        required: false

      param :permissions,
        type: "object",
        desc: "Tool permission restrictions (same format as swarm config). Only for type: skill",
        required: false

      # Initialize with storage instance
      #
      # @param storage [Core::Storage] Storage instance
      # @param agent_name [String, Symbol] Agent identifier
      def initialize(storage:, agent_name:)
        super()
        @storage = storage
        @agent_name = agent_name.to_sym
      end

      # Override name to return simple "MemoryWrite"
      def name
        "MemoryWrite"
      end

      # Execute the tool
      #
      # @param file_path [String] Path to store content (.md file)
      # @param content [String] Content to store (pure markdown)
      # @param title [String] Brief title
      # @param type [String, nil] Entry type
      # @param confidence [String, nil] Confidence level
      # @param tags [Array, nil] Tags
      # @param related [Array, nil] Related paths
      # @param domain [String, nil] Domain
      # @param source [String, nil] Source
      # @param tools [Array, nil] Tools required (for skills)
      # @param permissions [Hash, nil] Tool permissions (for skills)
      # @return [String] Success message
      def execute(
        file_path:,
        content:,
        title:,
        type:,
        confidence: nil,
        tags:,
        related:,
        domain:,
        source: nil,
        tools: nil,
        permissions: nil
      )
        # Validate content length (250 word limit)
        word_count = content.split(/\s+/).size
        if word_count > 250
          return validation_error(
            "Content exceeds 250-word limit (#{word_count} words). " \
              "Please extract the key entities and concepts from this content, then split it into multiple smaller, " \
              "focused memories (each under 250 words) that still capture ALL the important details. " \
              "Link related memories together using the 'related' metadata field with memory:// URIs. " \
              "Each memory should cover one specific aspect or concept while preserving completeness.",
          )
        end

        # Build metadata hash from params
        # Handle both JSON strings (from LLMs) and Ruby arrays (from tests/code)
        metadata = {}
        metadata["type"] = type if type
        metadata["confidence"] = confidence || "medium" # Default to medium
        metadata["tags"] = parse_array_param(tags) if tags
        metadata["related"] = parse_array_param(related) if related
        metadata["domain"] = domain if domain
        metadata["source"] = source || "user" # Default to user
        metadata["tools"] = parse_array_param(tools) if tools
        metadata["permissions"] = parse_object_param(permissions) if permissions

        # Write to storage (metadata passed separately, not in content)
        entry = @storage.write(
          file_path: file_path,
          content: content,
          title: title,
          metadata: metadata,
        )

        "Stored at memory://#{file_path} (#{format_bytes(entry.size)})"
      rescue ArgumentError => e
        validation_error(e.message)
      rescue JSON::ParserError => e
        validation_error("Invalid tool parameter JSON format: #{e.message}")
      end

      private

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end

      # Parse array parameter (handles both JSON strings and Ruby arrays)
      #
      # @param value [String, Array] JSON string or Ruby array
      # @return [Array] Parsed array
      def parse_array_param(value)
        return value if value.is_a?(Array)
        return [] if value.nil? || value.to_s.strip.empty?

        JSON.parse(value)
      end

      # Parse object parameter (handles both JSON strings and Ruby hashes)
      #
      # @param value [String, Hash] JSON string or Ruby hash
      # @return [Hash] Parsed hash
      def parse_object_param(value)
        return value if value.is_a?(Hash)
        return {} if value.nil? || value.to_s.strip.empty?

        begin
          JSON.parse(value)
        rescue JSON::ParserError => e
          # Handle common JSON errors gracefully
          warn("Warning: Failed to parse object parameter: #{e.message}. Returning empty object.")
          {}
        end
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
