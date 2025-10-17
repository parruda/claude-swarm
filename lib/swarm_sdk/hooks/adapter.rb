# frozen_string_literal: true

module SwarmSDK
  module Hooks
    # Translates YAML hooks configuration to Ruby hooks
    #
    # Adapter bridges the gap between declarative YAML hooks (shell commands)
    # and SwarmSDK's internal hook system. It creates hooks that execute
    # shell commands and translate exit codes to Result objects.
    #
    # ## YAML Hooks are YAML-Only
    #
    # Hooks are a **YAML-only feature** designed for users who want Claude Code-style
    # shell command hooks. Users of the Ruby API should use hooks directly.
    #
    # ## Swarm-Level vs Agent-Level
    #
    # - **Swarm-level**: Only `swarm_start` and `swarm_stop` (lifecycle hooks)
    # - **Agent-level**: All other events (per-agent or all_agents)
    # - **all_agents**: Hooks applied as swarm defaults to all agents
    #
    # ## Event Naming
    #
    # Uses snake_case to match internal hook events directly (no translation):
    # - `pre_tool_use` → :pre_tool_use
    # - `swarm_start` → :swarm_start
    # - etc.
    #
    # @example YAML configuration
    #   swarm:
    #     hooks:
    #       swarm_start:
    #         - hooks:
    #             - type: command
    #               command: "echo 'Starting swarm'"
    #
    #     all_agents:
    #       hooks:
    #         pre_tool_use:
    #           - matcher: "Write|Edit"
    #             hooks:
    #               - type: command
    #                 command: "rubocop --stdin"
    #
    #     agents:
    #       backend:
    #         hooks:
    #           pre_tool_use:
    #             - matcher: "Bash"
    #               hooks:
    #                 - type: command
    #                   command: "python validate_bash.py"
    class Adapter
      # Swarm-level events (only these allowed at swarm.hooks level)
      SWARM_LEVEL_EVENTS = [:swarm_start, :swarm_stop].freeze

      # Agent-level events (allowed in all_agents.hooks and agent.hooks)
      AGENT_LEVEL_EVENTS = [
        :pre_tool_use,
        :post_tool_use,
        :user_prompt,
        :agent_step,
        :agent_stop,
        :first_message,
        :pre_delegation,
        :post_delegation,
        :context_warning,
      ].freeze

      class << self
        # Apply hooks from YAML configuration to swarm
        #
        # This is called automatically by Swarm.load after creating the swarm instance.
        # It translates YAML hooks into hooks that execute shell commands.
        #
        # @param swarm [Swarm] Swarm instance to configure
        # @param config [Configuration] Parsed YAML configuration
        # @return [void]
        def apply_hooks(swarm, config)
          # 1. Apply swarm-level hooks (from swarm.hooks)
          apply_swarm_hooks(swarm, config.swarm_hooks) if config.swarm_hooks&.any?

          # 2. Apply all_agents hooks (as swarm defaults)
          apply_all_agents_hooks(swarm, config.all_agents_hooks) if config.all_agents_hooks&.any?

          # 3. Store agent hooks for later application (after agents are initialized)
          store_agent_hooks(config)
        end

        # Apply agent-specific hooks to an already-initialized agent
        #
        # This is called during agent initialization for each agent that has hooks configured.
        #
        # @param agent [AgentChat] Agent instance
        # @param agent_name [Symbol] Agent name
        # @param hooks_config [Hash] Hooks configuration from YAML
        # @param swarm_name [String] Swarm name for environment variables
        # @return [void]
        def apply_agent_hooks(agent, agent_name, hooks_config, swarm_name)
          return unless hooks_config&.any?

          hooks_config.each do |event_name, hook_defs|
            event_symbol = event_name.to_sym
            validate_agent_event!(event_symbol)

            # Each hook def can have optional matcher
            Array(hook_defs).each do |hook_def|
              matcher = hook_def[:matcher] || hook_def["matcher"]
              hook = create_hook_callback(hook_def, event_symbol, agent_name, swarm_name)
              agent.add_hook(event_symbol, matcher: matcher, &hook)
            end
          end
        end

        private

        # Apply swarm-level hooks (swarm_start, swarm_stop)
        #
        # @param swarm [Swarm] Swarm instance
        # @param hooks_config [Hash] Hooks configuration
        def apply_swarm_hooks(swarm, hooks_config)
          hooks_config.each do |event_name, hook_defs|
            event_symbol = event_name.to_sym
            validate_swarm_event!(event_symbol)

            # Each hook def is a direct hash with type, command, timeout
            Array(hook_defs).each do |hook_def|
              hook = create_swarm_hook_callback(hook_def, event_symbol, swarm.name)
              swarm.add_default_callback(event_symbol, &hook)
            end
          end
        end

        # Apply all_agents hooks as swarm defaults
        #
        # @param swarm [Swarm] Swarm instance
        # @param hooks_config [Hash] Hooks configuration
        def apply_all_agents_hooks(swarm, hooks_config)
          hooks_config.each do |event_name, hook_defs|
            event_symbol = event_name.to_sym
            validate_agent_event!(event_symbol)

            # Each hook def can have optional matcher
            Array(hook_defs).each do |hook_def|
              matcher = hook_def[:matcher] || hook_def["matcher"]
              hook = create_all_agents_hook_callback(hook_def, event_symbol, swarm.name)
              swarm.add_default_callback(event_symbol, matcher: matcher, &hook)
            end
          end
        end

        # Store agent hooks in Configuration for later application
        #
        # @param config [Configuration] Configuration instance
        def store_agent_hooks(config)
          # Agent hooks are already stored in AgentDefinition
          # They'll be applied during agent initialization
        end

        # Create a hook for agent-level hooks
        #
        # @param hook_def [Hash] Hook definition from YAML
        # @param event_symbol [Symbol] Event type
        # @param agent_name [Symbol, String] Agent name
        # @param swarm_name [String] Swarm name
        # @return [Proc] Hook callback
        def create_hook_callback(hook_def, event_symbol, agent_name, swarm_name)
          # Support both string and symbol keys (YAML may be symbolized)
          command = hook_def[:command] || hook_def["command"]
          timeout = hook_def[:timeout] || hook_def["timeout"] || ShellExecutor::DEFAULT_TIMEOUT

          lambda do |context|
            input_json = build_input_json(context, event_symbol, agent_name)
            ShellExecutor.execute(
              command: command,
              input_json: input_json,
              timeout: timeout,
              agent_name: agent_name,
              swarm_name: swarm_name,
              event: event_symbol,
            )
          end
        end

        # Create a hook for all_agents hooks
        #
        # @param hook_def [Hash] Hook definition from YAML
        # @param event_symbol [Symbol] Event type
        # @param swarm_name [String] Swarm name
        # @return [Proc] Hook callback
        def create_all_agents_hook_callback(hook_def, event_symbol, swarm_name)
          # Support both string and symbol keys (YAML may be symbolized)
          command = hook_def[:command] || hook_def["command"]
          timeout = hook_def[:timeout] || hook_def["timeout"] || ShellExecutor::DEFAULT_TIMEOUT

          lambda do |context|
            # Agent name comes from context
            agent_name = context.agent_name
            input_json = build_input_json(context, event_symbol, agent_name)
            ShellExecutor.execute(
              command: command,
              input_json: input_json,
              timeout: timeout,
              agent_name: agent_name,
              swarm_name: swarm_name,
              event: event_symbol,
            )
          end
        end

        # Create a hook for swarm-level hooks
        #
        # @param hook_def [Hash] Hook definition from YAML
        # @param event_symbol [Symbol] Event type
        # @param swarm_name [String] Swarm name
        # @return [Proc] Hook callback
        def create_swarm_hook_callback(hook_def, event_symbol, swarm_name)
          # Support both string and symbol keys (YAML may be symbolized)
          command = hook_def[:command] || hook_def["command"]
          timeout = hook_def[:timeout] || hook_def["timeout"] || ShellExecutor::DEFAULT_TIMEOUT

          lambda do |context|
            input_json = build_swarm_input_json(context, event_symbol, swarm_name)
            ShellExecutor.execute(
              command: command,
              input_json: input_json,
              timeout: timeout,
              agent_name: nil,
              swarm_name: swarm_name,
              event: event_symbol,
            )
          end
        end

        # Build JSON input for agent-level hook scripts
        #
        # @param context [Context] Hook context
        # @param event_symbol [Symbol] Event type
        # @param agent_name [Symbol, String] Agent name
        # @return [Hash] JSON input for hook script
        def build_input_json(context, event_symbol, agent_name)
          base = {
            event: event_symbol.to_s,
            agent: agent_name.to_s,
          }

          # Add event-specific data
          case event_symbol
          when :pre_tool_use
            base.merge(
              tool: context.tool_call.name,
              parameters: context.tool_call.parameters,
            )
          when :post_tool_use
            # In post_tool_use, we only have tool_result, not tool_call
            # Need to extract tool info from metadata or tool_result
            base.merge(
              result: context.tool_result.content,
              success: context.tool_result.success?,
              tool_call_id: context.tool_result.tool_call_id,
            )
          when :pre_delegation
            base.merge(
              delegation_target: context.delegation_target,
              task: context.metadata[:task],
            )
          when :post_delegation
            base.merge(
              delegation_target: context.delegation_target,
              task: context.metadata[:task],
              result: context.delegation_result,
            )
          when :user_prompt
            base.merge(
              prompt: context.metadata[:prompt],
              message_count: context.metadata[:message_count],
            )
          when :agent_step
            base.merge(
              content: context.metadata[:content],
              tool_calls: context.metadata[:tool_calls],
              finish_reason: context.metadata[:finish_reason],
              usage: context.metadata[:usage],
            )
          when :agent_stop
            base.merge(
              content: context.metadata[:content],
              finish_reason: context.metadata[:finish_reason],
              usage: context.metadata[:usage],
            )
          when :first_message
            base.merge(prompt: context.metadata[:prompt])
          when :context_warning
            base.merge(
              threshold: context.metadata[:threshold],
              percentage: context.metadata[:percentage],
              tokens_used: context.metadata[:tokens_used],
              tokens_remaining: context.metadata[:tokens_remaining],
            )
          else
            base
          end
        end

        # Build JSON input for swarm-level hook scripts
        #
        # @param context [Context] Hook context
        # @param event_symbol [Symbol] Event type
        # @param swarm_name [String] Swarm name
        # @return [Hash] JSON input for hook script
        def build_swarm_input_json(context, event_symbol, swarm_name)
          base = {
            event: event_symbol.to_s,
            swarm: swarm_name,
          }

          case event_symbol
          when :swarm_start, :first_message
            base.merge(prompt: context.metadata[:prompt])
          when :swarm_stop
            base.merge(
              success: context.metadata[:success],
              duration: context.metadata[:duration],
              total_cost: context.metadata[:total_cost],
              total_tokens: context.metadata[:total_tokens],
            )
          else
            base
          end
        end

        # Validate swarm-level event
        #
        # @param event [Symbol] Event to validate
        # @raise [ConfigurationError] if event invalid for swarm level
        def validate_swarm_event!(event)
          return if SWARM_LEVEL_EVENTS.include?(event)

          raise ConfigurationError,
            "Invalid swarm-level hook event: #{event}. " \
              "Only #{SWARM_LEVEL_EVENTS.join(", ")} are allowed at swarm.hooks level. " \
              "Use all_agents.hooks or agent.hooks for other events."
        end

        # Validate agent-level event
        #
        # @param event [Symbol] Event to validate
        # @raise [ConfigurationError] if event invalid for agent level
        def validate_agent_event!(event)
          return if AGENT_LEVEL_EVENTS.include?(event)

          raise ConfigurationError,
            "Invalid agent-level hook event: #{event}. " \
              "Valid events: #{AGENT_LEVEL_EVENTS.join(", ")}"
        end
      end
    end
  end
end
