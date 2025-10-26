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
        Load a skill from memory and dynamically adapt your toolset to execute it.

        REQUIRED: Provide the file_path parameter - path to the skill in memory (must start with 'skill/').

        **Parameters:**
        - file_path (REQUIRED): Path to skill in memory - MUST start with 'skill/' (e.g., 'skill/debug-react-perf', 'skill/meta/deep-learning')

        **What Happens When You Load a Skill:**

        1. **Tool Swapping**: Your mutable tools are replaced with the skill's required tools
           - Immutable tools (Memory*, LoadSkill) always remain available
           - Skill's tool list completely replaces your current mutable tools

        2. **Permissions Applied**: Tool permissions from skill metadata are applied
           - Skill permissions override agent default permissions
           - Allows/denies specific tool actions as defined in skill

        3. **Skill Content Returned**: Returns the skill's step-by-step instructions
           - Read and follow the instructions carefully
           - Instructions are formatted with line numbers

        4. **System Reminder Injected**: You'll see your complete updated toolset
           - Lists all tools now available to you
           - Only use tools from the updated list

        **Skill Requirements:**

        Skills MUST:
        - Be stored in skill/ hierarchy ONLY (skill/ is one of exactly 4 memory categories)
        - Path MUST start with 'skill/' (e.g., 'skill/debugging/api.md', 'skill/meta/deep-learning.md')
        - Have type: 'skill' in metadata
        - Optionally specify tools array in metadata
        - Optionally specify permissions hash in metadata

        **MEMORY CATEGORIES (4 Fixed Only):**
        concept/, fact/, skill/, experience/ - NO OTHER top-level categories exist

        **Skill Metadata Example:**
        ```yaml
        type: skill
        tools: [Read, Edit, Bash, Grep]
        permissions:
          Bash:
            allow_commands: ["npm", "pytest", "bundle"]
            deny_commands: ["rm", "sudo"]
        tags: [debugging, react, performance]
        ```

        **Usage Flow:**

        ```
        # 1. Find available skills (skill/ is one of 4 fixed memory categories)
        MemoryGlob(pattern: "skill/**")

        # 2. Read skill to understand it
        MemoryRead(file_path: "skill/debugging/api-errors.md")

        # 3. Load skill to adapt tools and get instructions
        LoadSkill(file_path: "skill/debugging/api-errors.md")

        # 4. Follow the skill's instructions using your updated toolset
        ```

        **Examples:**

        ```
        # Load a debugging skill
        LoadSkill(file_path: "skill/debugging/api-errors.md")

        # Load a meta-skill (skills about skills)
        LoadSkill(file_path: "skill/meta/deep-learning.md")

        # Load a testing skill
        LoadSkill(file_path: "skill/testing/unit-tests.md")
        ```

        **Important Notes:**

        - **Read Before Loading**: Use MemoryRead first to see what the skill does
        - **Tool Swap**: Loading a skill changes your available tools - be aware of this
        - **Immutable Tools**: Memory tools and LoadSkill are NEVER removed
        - **Follow Instructions**: The skill content provides step-by-step guidance
        - **One Skill at a Time**: Loading a new skill replaces the previous skill's toolset
        - **Skill Validation**: Tool will fail if path doesn't start with 'skill/' or entry isn't type: 'skill'

        **Skill Types:**

        1. **Task Skills**: Specific procedures (debugging, testing, refactoring)
        2. **Meta-Skills**: Skills about skills (deep-learning, skill-creation)
        3. **Domain Skills**: Specialized knowledge (frontend, backend, data-analysis)

        **Creating Your Own Skills:**

        Skills are just memory entries with special metadata. To create one:
        1. Write step-by-step instructions in markdown
        2. Store in skill/ hierarchy
        3. Add metadata: type='skill', tools array, optional permissions
        4. Test by loading and following instructions

        **Common Use Cases:**

        - Following established procedures consistently
        - Accessing specialized toolsets for specific tasks
        - Learning new workflows via step-by-step guidance
        - Enforcing tool restrictions for safety
        - Standardizing approaches across sessions
      DESC

      param :file_path,
        desc: "Path to skill - MUST start with 'skill/' (one of 4 fixed memory categories). Examples: 'skill/debugging/api-errors.md', 'skill/meta/deep-learning.md'",
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
        result = "Loaded skill: #{title}\n\n"
        result += format_with_line_numbers(entry.content)

        # 8. Add system reminder if tools were swapped
        if required_tools && !required_tools.empty?
          result += "\n\n"
          result += build_toolset_update_reminder(required_tools)
        end

        result
      end

      private

      # Build system reminder for toolset updates
      #
      # @param new_tools [Array<String>] Tools that were added
      # @return [String] System reminder message
      def build_toolset_update_reminder(new_tools)
        # Get current tool list from chat
        # Handle both real Chat (hash) and MockChat (array)
        tools_collection = @chat.tools
        current_tools = if tools_collection.is_a?(Hash)
          tools_collection.values.map(&:name).sort
        else
          tools_collection.map(&:name).sort
        end

        reminder = "<system-reminder>\n"
        reminder += "Your available tools have been updated.\n\n"
        reminder += "New tools loaded from skill:\n"
        new_tools.each do |tool_name|
          reminder += "  - #{tool_name}\n"
        end
        reminder += "\nYour complete toolset is now:\n"
        current_tools.each do |tool_name|
          reminder += "  - #{tool_name}\n"
        end
        reminder += "\nOnly use tools from this list. Do not attempt to use tools that are not listed here.\n"
        reminder += "</system-reminder>"

        reminder
      end

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
