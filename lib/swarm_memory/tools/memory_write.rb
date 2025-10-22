# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for writing content to memory storage
    #
    # Stores content and metadata in persistent, per-agent memory storage.
    # Each agent has its own isolated memory storage that persists across sessions.
    class MemoryWrite < RubyLLM::Tool
      description <<~DESC
        Store content in memory for later retrieval with structured metadata.

        Content is stored in .md files, metadata in sidecar .yml files.
        You only reference .md files - the .yml sidecars are managed automatically.

        Choose logical paths based on content type:
        - concept/ruby/classes.md - Abstract ideas
        - fact/people/paulo.md - Concrete information
        - skill/ruby/testing.md - How-to procedures
        - experience/bug-fix.md - Lessons learned
      DESC

      param :file_path,
        desc: "Path with .md extension (e.g., 'concept/ruby/classes.md', 'fact/people/paulo.md')",
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
        desc: "Confidence level: high, medium, or low",
        required: true

      param :tags,
        type: "array",
        desc: "Tags for searching (e.g., ['ruby', 'oop'])",
        required: true

      param :related,
        type: "array",
        desc: "Related memory paths (e.g., ['memory://concepts/ruby/modules.md'])",
        required: true

      param :domain,
        desc: "Category/subcategory (e.g., 'programming/ruby', 'people')",
        required: true

      param :source,
        desc: "Source of information: user, documentation, experimentation, or inference",
        required: true

      param :tools,
        type: "array",
        desc: "Tools required for this skill (e.g., ['Read', 'Edit', 'Bash']). Only for type: skill",
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
        confidence:,
        tags:,
        related:,
        domain:,
        source:,
        tools: nil,
        permissions: nil
      )
        # Build metadata hash from params
        metadata = {}
        metadata["type"] = type if type
        metadata["confidence"] = confidence if confidence
        metadata["tags"] = tags if tags
        metadata["related"] = related if related
        metadata["domain"] = domain if domain
        metadata["source"] = source if source
        metadata["tools"] = tools if tools
        metadata["permissions"] = permissions if permissions

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
