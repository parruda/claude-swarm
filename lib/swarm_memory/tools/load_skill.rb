# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for loading skills from memory and dynamically swapping agent tools
    #
    # LoadSkill reads a skill from memory, validates it, and swaps the agent's
    # mutable tools to match the skill's requirements. Immutable tools (Memory*,
    # Think, LoadSkill) are always preserved.
    #
    # Skills must:
    # - Be stored in the skill/ hierarchy
    # - Have type: 'skill' in metadata
    # - Include tools array in metadata (optional)
    # - Include permissions hash in metadata (optional)
    class LoadSkill < RubyLLM::Tool
      description <<~DESC
        Load a skill from memory and adapt your tools to execute it.

        When you load a skill:
        1. Your mutable tools are swapped to match the skill's requirements
        2. Immutable tools (Memory*, Think, LoadSkill) always remain available
        3. Tool permissions from the skill are applied
        4. Returns the skill content (step-by-step instructions)

        Skills must be stored in the skill/ hierarchy with type: 'skill' in metadata.

        Example:
          LoadSkill(file_path: "skill/debug-react-perf.md")
      DESC

      param :file_path,
        desc: "Path to skill in memory (must start with 'skill/', e.g., 'skill/debug-react-perf.md')",
        required: true

      # Initialize with all context needed for tool swapping
      #
      # @param storage [Core::Storage] Memory storage
      # @param agent_name [Symbol] Agent identifier
      # @param chat [SwarmSDK::Agent::Chat] The agent's chat instance
      # @param tool_configurator [SwarmSDK::ToolConfigurator] For creating tools
      # @param agent_definition [SwarmSDK::Agent::Definition] For permissions
      def initialize(storage:, agent_name:, chat:, tool_configurator:, agent_definition:)
        super()
        @storage = storage
        @agent_name = agent_name
        @chat = chat
        @tool_configurator = tool_configurator
        @agent_definition = agent_definition

        # Mark memory tools and LoadSkill as immutable
        # This ensures they won't be removed during skill swapping
        @chat.mark_tools_immutable(
          "MemoryWrite",
          "MemoryRead",
          "MemoryEdit",
          "MemoryMultiEdit",
          "MemoryDelete",
          "MemoryGlob",
          "MemoryGrep",
          "MemoryDefrag",
          "LoadSkill",
        )
      end

      # Override name to return simple "LoadSkill"
      def name
        "LoadSkill"
      end

      # Execute the tool
      #
      # @param file_path [String] Path to skill in memory
      # @return [String] Skill content with line numbers, or error message
      def execute(file_path:)
        # 1. Validate path starts with skill/
        unless file_path.start_with?("skill/")
          return validation_error("Skills must be stored in skill/ hierarchy. Got: #{file_path}")
        end

        # 2. Read entry with metadata
        begin
          entry = @storage.read_entry(file_path: file_path)
        rescue ArgumentError => e
          return validation_error(e.message)
        end

        # 3. Validate it's a skill
        unless entry.metadata && entry.metadata["type"] == "skill"
          type = entry.metadata&.dig("type") || "none"
          return validation_error("memory://#{file_path} is not a skill (type: #{type})")
        end

        # 4. Extract tool requirements
        required_tools = entry.metadata["tools"]
        permissions = entry.metadata["permissions"] || {}

        # 5. Validate and swap tools (only if tools are specified)
        if required_tools && !required_tools.empty?
          begin
            swap_tools(required_tools, permissions)
          rescue ArgumentError => e
            return validation_error(e.message)
          end
        end
        # If no tools specified (nil or []), keep current tools (no swap)

        # 6. Mark skill as loaded
        @chat.mark_skill_loaded(file_path)

        # 7. Return content with confirmation message
        title = entry.title || "Untitled Skill"
        "Loaded skill: #{title}\n\n" + format_with_line_numbers(entry.content)
      end

      private

      # Swap agent tools to match skill requirements
      #
      # @param required_tools [Array<String>] Tools needed by the skill
      # @param permissions [Hash] Tool permissions from skill metadata
      # @return [void]
      # @raise [ArgumentError] If validation fails
      def swap_tools(required_tools, permissions)
        # Future: Could validate tool availability against agent's configured tools
        # For now, all tools in SwarmSDK are available (unless bypassed by permissions)

        # Remove all mutable tools (keeps immutable tools)
        @chat.remove_mutable_tools

        # Add required tools from skill
        required_tools.each do |tool_name|
          tool_sym = tool_name.to_sym

          # Get permissions for this tool (skill overrides agent permissions)
          tool_permissions = permissions[tool_name] || permissions[tool_sym.to_s]

          # Create tool instance
          tool_instance = @tool_configurator.create_tool_instance(
            tool_sym,
            @agent_name,
            @agent_definition.directory,
          )

          # Wrap with permissions (unless bypassed)
          tool_instance = @tool_configurator.wrap_tool_with_permissions(
            tool_instance,
            tool_permissions,
            @agent_definition,
          )

          # Add to chat
          @chat.add_tool(tool_instance)
        end
      end

      # Format validation error message
      #
      # @param message [String] Error message
      # @return [String] Formatted error
      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end

      # Format content with line numbers (same format as Read tool)
      #
      # @param content [String] Content to format
      # @return [String] Content with line numbers
      def format_with_line_numbers(content)
        lines = content.lines
        output_lines = lines.each_with_index.map do |line, idx|
          line_number = idx + 1
          display_line = line.chomp
          "#{line_number.to_s.rjust(6)}→#{display_line}"
        end
        output_lines.join("\n")
      end
    end
  end
end
