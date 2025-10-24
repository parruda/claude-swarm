# frozen_string_literal: true

module SwarmMemory
  module Integration
    # SwarmSDK plugin implementation for SwarmMemory
    #
    # This plugin integrates SwarmMemory with SwarmSDK, providing:
    # - Persistent memory storage for agents
    # - Memory tools (MemoryWrite, MemoryRead, MemoryEdit, etc.)
    # - LoadSkill tool for dynamic tool swapping
    # - System prompt contributions for memory guidance
    # - Semantic skill discovery on user messages
    #
    # The plugin automatically registers itself when SwarmMemory is loaded
    # alongside SwarmSDK.
    class SDKPlugin < SwarmSDK::Plugin
      def initialize
        super
        # Track storages for each agent: { agent_name => storage }
        # Needed for semantic skill discovery in on_user_message
        @storages = {}
      end

      # Plugin identifier
      #
      # @return [Symbol] Plugin name
      def name
        :memory
      end

      # Tools provided by this plugin
      #
      # Note: LoadSkill is NOT included here because it requires special handling.
      # It's registered separately in on_agent_initialized lifecycle hook because
      # it needs chat, tool_configurator, and agent_definition parameters.
      #
      # @return [Array<Symbol>] Memory tool names
      def tools
        [
          :MemoryWrite,
          :MemoryRead,
          :MemoryEdit,
          :MemoryMultiEdit,
          :MemoryGlob,
          :MemoryGrep,
          :MemoryDelete,
          :MemoryDefrag,
        ]
      end

      # Create a tool instance
      #
      # @param tool_name [Symbol] Tool name
      # @param context [Hash] Creation context with :storage, :agent_name, :chat, etc.
      # @return [RubyLLM::Tool] Tool instance
      def create_tool(tool_name, context)
        storage = context[:storage]
        agent_name = context[:agent_name]

        # Delegate to SwarmMemory's tool factory
        SwarmMemory.create_tool(tool_name, storage: storage, agent_name: agent_name)
      end

      # Create plugin storage for an agent
      #
      # @param agent_name [Symbol] Agent identifier
      # @param config [Object] Memory configuration (MemoryConfig or Hash)
      # @return [Core::Storage] Storage instance with embeddings enabled
      def create_storage(agent_name:, config:)
        # Extract directory from config
        memory_dir = if config.respond_to?(:directory)
          config.directory # MemoryConfig object (from DSL)
        else
          config[:directory] || config["directory"] # Hash (from YAML)
        end

        raise SwarmSDK::ConfigurationError, "Memory directory not configured for #{agent_name}" unless memory_dir

        # Create embedder for semantic search
        embedder = Embeddings::InformersEmbedder.new

        # Create filesystem adapter
        adapter = Adapters::FilesystemAdapter.new(directory: memory_dir)

        # Create storage with embedder (enables semantic features)
        Core::Storage.new(adapter: adapter, embedder: embedder)
      end

      # Parse memory configuration
      #
      # @param raw_config [Object] Raw config (MemoryConfig or Hash)
      # @return [Object] Parsed configuration
      def parse_config(raw_config)
        # Already parsed by Agent::Definition, just return as-is
        raw_config
      end

      # Contribute to agent system prompt
      #
      # @param agent_definition [Agent::Definition] Agent definition
      # @param storage [Core::Storage, nil] Storage instance (may be nil during prompt building)
      # @return [String] Memory prompt contribution
      def system_prompt_contribution(agent_definition:, storage:)
        # Load memory prompt template
        memory_prompt_path = File.expand_path("../prompts/memory.md.erb", __dir__)
        template_content = File.read(memory_prompt_path)

        # Render with agent_definition binding
        ERB.new(template_content).result(agent_definition.instance_eval { binding })
      end

      # Tools that should be marked immutable
      #
      # All memory tools plus LoadSkill are immutable to prevent accidental removal.
      #
      # @return [Array<Symbol>] Immutable tool names
      def immutable_tools
        [
          :MemoryWrite,
          :MemoryRead,
          :MemoryEdit,
          :MemoryMultiEdit,
          :MemoryGlob,
          :MemoryGrep,
          :MemoryDelete,
          :MemoryDefrag,
          :LoadSkill,
        ]
      end

      # Check if storage should be created for this agent
      #
      # @param agent_definition [Agent::Definition] Agent definition
      # @return [Boolean] True if agent has memory configuration
      def storage_enabled?(agent_definition)
        agent_definition.memory_enabled?
      end

      # Lifecycle: Agent initialized
      #
      # Register LoadSkill tool and mark all memory tools as immutable.
      # LoadSkill needs special handling because it requires chat, tool_configurator,
      # and agent_definition to perform dynamic tool swapping.
      #
      # @param agent_name [Symbol] Agent identifier
      # @param agent [Agent::Chat] Chat instance
      # @param context [Hash] Initialization context
      def on_agent_initialized(agent_name:, agent:, context:)
        storage = context[:storage]
        agent_definition = context[:agent_definition]
        tool_configurator = context[:tool_configurator]

        return unless storage # Only proceed if memory is enabled for this agent

        # Store storage for this agent (needed for on_user_message)
        @storages[agent_name] = storage

        # Create and register LoadSkill tool
        load_skill_tool = SwarmMemory.create_tool(
          :LoadSkill,
          storage: storage,
          agent_name: agent_name,
          chat: agent,
          tool_configurator: tool_configurator,
          agent_definition: agent_definition,
        )

        agent.with_tool(load_skill_tool)

        # Mark all memory tools as immutable
        agent.mark_tools_immutable(immutable_tools.map(&:to_s))
      end

      # Lifecycle: User message
      #
      # Performs TWO semantic searches:
      # 1. Skills - For loadable procedures with LoadSkill
      # 2. Memories - For concepts/facts/experiences that provide context
      #
      # Returns system reminders for both if high-confidence matches found.
      #
      # @param agent_name [Symbol] Agent identifier
      # @param prompt [String] User's message
      # @param is_first_message [Boolean] True if first message
      # @return [Array<String>] System reminders (0-2 reminders)
      def on_user_message(agent_name:, prompt:, is_first_message:)
        storage = @storages[agent_name]
        return [] unless storage&.semantic_index

        # Configurable via environment variable for tuning
        # Optimal: 0.60 (discovered via systematic evaluation)
        threshold = (ENV["SWARM_MEMORY_DISCOVERY_THRESHOLD"] || "0.60").to_f
        reminders = []

        # Run both searches in parallel with Async
        Async do |task|
          # Search 1: Skills (type = "skill")
          skills_task = task.async do
            storage.semantic_index.search(
              query: prompt,
              top_k: 3,
              threshold: threshold,
              filter: { "type" => "skill" },
            )
          end

          # Search 2: All results (for memories + logging)
          all_results_task = task.async do
            storage.semantic_index.search(
              query: prompt,
              top_k: 10,
              threshold: 0.0, # Get all for logging
              filter: nil,
            )
          end

          # Wait for both searches to complete
          skills = skills_task.wait
          all_results = all_results_task.wait

          # Filter to concepts, facts, experiences (not skills)
          memories = all_results
            .select { |r| ["concept", "fact", "experience"].include?(r.dig(:metadata, "type")) }
            .select { |r| r[:similarity] >= threshold }
            .take(3)

          # Emit log events
          emit_skill_search_log(agent_name, prompt, skills, all_results, threshold)
          emit_memory_search_log(agent_name, prompt, memories, threshold)

          # Build skill reminder if found
          if skills.any?
            reminders << build_skill_discovery_reminder(skills)
          end

          # Build memory reminder if found
          if memories.any?
            reminders << build_memory_discovery_reminder(memories)
          end
        end.wait

        reminders
      end

      private

      # Emit log event for semantic skill search
      #
      # @param agent_name [Symbol] Agent identifier
      # @param prompt [String] User's message
      # @param skills [Array<Hash>] Found skills (filtered)
      # @param all_results [Array<Hash>] All search results (unfiltered)
      # @param threshold [Float] Similarity threshold used
      # @return [void]
      def emit_skill_search_log(agent_name, prompt, skills, all_results, threshold)
        return unless SwarmSDK::LogStream.enabled?

        # Include top 5 results for debugging (even if below threshold or wrong type)
        all_entries_debug = all_results.take(5).map do |result|
          {
            path: result[:path],
            title: result[:title],
            hybrid_score: result[:similarity].round(3),
            semantic_score: result[:semantic_score]&.round(3),
            keyword_score: result[:keyword_score]&.round(3),
            type: result.dig(:metadata, "type"),
            tags: result.dig(:metadata, "tags"),
          }
        end

        # Get actual weights being used (from ENV or defaults)
        semantic_weight = (ENV["SWARM_MEMORY_SEMANTIC_WEIGHT"] || "0.5").to_f
        keyword_weight = (ENV["SWARM_MEMORY_KEYWORD_WEIGHT"] || "0.5").to_f

        SwarmSDK::LogStream.emit(
          type: "semantic_skill_search",
          agent: agent_name,
          query: prompt,
          threshold: threshold,
          skills_found: skills.size,
          total_entries_searched: all_results.size,
          search_mode: "hybrid",
          weights: { semantic: semantic_weight, keyword: keyword_weight },
          skills: skills.map do |skill|
            {
              path: skill[:path],
              title: skill[:title],
              hybrid_score: skill[:similarity].round(3),
              semantic_score: skill[:semantic_score]&.round(3),
              keyword_score: skill[:keyword_score]&.round(3),
            }
          end,
          debug_top_results: all_entries_debug,
        )
      end

      # Emit log event for semantic memory search
      #
      # @param agent_name [Symbol] Agent identifier
      # @param prompt [String] User's message
      # @param memories [Array<Hash>] Found memories (concepts/facts/experiences)
      # @param threshold [Float] Similarity threshold used
      # @return [void]
      def emit_memory_search_log(agent_name, prompt, memories, threshold)
        return unless SwarmSDK::LogStream.enabled?

        # Get actual weights being used (from ENV or defaults)
        semantic_weight = (ENV["SWARM_MEMORY_SEMANTIC_WEIGHT"] || "0.5").to_f
        keyword_weight = (ENV["SWARM_MEMORY_KEYWORD_WEIGHT"] || "0.5").to_f

        SwarmSDK::LogStream.emit(
          type: "semantic_memory_search",
          agent: agent_name,
          query: prompt,
          threshold: threshold,
          memories_found: memories.size,
          search_mode: "hybrid",
          weights: { semantic: semantic_weight, keyword: keyword_weight },
          memories: memories.map do |memory|
            {
              path: memory[:path],
              title: memory[:title],
              type: memory.dig(:metadata, "type"),
              hybrid_score: memory[:similarity].round(3),
              semantic_score: memory[:semantic_score]&.round(3),
              keyword_score: memory[:keyword_score]&.round(3),
            }
          end,
        )
      end

      # Build system reminder for discovered skills
      #
      # @param skills [Array<Hash>] Skill search results
      # @return [String] Formatted system reminder
      def build_skill_discovery_reminder(skills)
        reminder = "<system-reminder>\n"
        reminder += "🎯 Found #{skills.size} skill(s) in memory that may be relevant:\n\n"

        skills.each do |skill|
          match_pct = (skill[:similarity] * 100).round
          reminder += "**#{skill[:title]}** (#{match_pct}% match)\n"
          reminder += "Path: `#{skill[:path]}`\n"
          reminder += "To use: `LoadSkill(file_path: \"#{skill[:path]}\")`\n\n"
        end

        reminder += "**If a skill matches your task:** Load it to get step-by-step instructions and adapted tools.\n"
        reminder += "**If none match (false positive):** Ignore and proceed normally.\n"
        reminder += "</system-reminder>"

        reminder
      end

      # Build system reminder for discovered memories
      #
      # @param memories [Array<Hash>] Memory search results (concepts/facts/experiences)
      # @return [String] Formatted system reminder
      def build_memory_discovery_reminder(memories)
        reminder = "<system-reminder>\n"
        reminder += "📚 Found #{memories.size} memory entr#{memories.size == 1 ? "y" : "ies"} that may provide context:\n\n"

        memories.each do |memory|
          match_pct = (memory[:similarity] * 100).round
          type = memory.dig(:metadata, "type")
          type_emoji = case type
          when "concept" then "💡"
          when "fact" then "📋"
          when "experience" then "🔍"
          else "📄"
          end

          reminder += "#{type_emoji} **#{memory[:title]}** (#{type}, #{match_pct}% match)\n"
          reminder += "Path: `#{memory[:path]}`\n"
          reminder += "Read with: `MemoryRead(file_path: \"#{memory[:path]}\")`\n\n"
        end

        reminder += "**These entries may contain relevant knowledge for your task.**\n"
        reminder += "Read them to inform your approach, or ignore if not helpful.\n"
        reminder += "</system-reminder>"

        reminder
      end
    end
  end
end
