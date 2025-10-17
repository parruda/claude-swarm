# frozen_string_literal: true

module SwarmSDK
  module Hooks
    # Executes hooks with proper chaining, error handling, and logging
    #
    # The executor:
    # - Chains multiple hooks for the same event
    # - Handles errors and blocking (via Error or Result.halt)
    # - Respects matcher patterns (only runs matching hooks)
    # - Logs execution for debugging
    # - Returns Result indicating action to take
    #
    # @example Execute hooks
    #   executor = SwarmSDK::Hooks::Executor.new(registry, logger)
    #   context = SwarmSDK::Hooks::Context.new(...)
    #   result = executor.execute(event: :pre_tool_use, context: context, hooks: agent_hooks)
    #   if result.halt?
    #     # Handle halt
    #   elsif result.replace?
    #     # Use replacement value
    #   end
    class Executor
      # @param registry [Registry] Hook registry for resolving named hooks
      # @param logger [Logger, nil] Logger for debugging (optional)
      def initialize(registry, logger: nil)
        @registry = registry
        @logger = logger || Logger.new(nil) # Null logger if not provided
      end

      # Execute all hooks for an event
      #
      # Execution order:
      # 1. Swarm-level defaults (from registry)
      # 2. Agent-specific hooks
      # 3. Within each group, by priority (highest first)
      #
      # Hooks must return:
      # - Result - to control execution flow (halt, replace, reprompt, continue)
      # - nil - treated as continue with unmodified context
      #
      # @param event [Symbol] Event type
      # @param context [Context] Context to pass to hooks
      # @param callbacks [Array<Definition>] Agent-specific hooks
      # @return [Result] Result indicating action and value
      # @raise [Error] If a hook raises an error
      def execute(event:, context:, callbacks: [])
        # Combine swarm defaults and agent hooks
        all_hooks = @registry.get_defaults(event) + callbacks

        # Filter by matcher (for tool events)
        if context.tool_event? && context.tool_name
          all_hooks = all_hooks.select { |hook| hook.matches?(context.tool_name) }
        end

        # Execute hooks in order
        all_hooks.each do |hook_def|
          result = execute_single(hook_def, context)

          # Only Result controls flow - nil means continue
          next unless result.is_a?(Result)

          # Early return for control flow actions
          return result if result.halt? || result.replace? || result.reprompt? || result.finish_agent? || result.finish_swarm?

          # Update context if continue with modified context
          context = result.value if result.continue? && result.value.is_a?(Context)
        end

        # All hooks executed successfully - continue with final context
        Result.continue(context)
      rescue Error => e
        # Re-raise with context for better error messages
        @logger.error("Hook blocked execution: #{e.message}")
        raise
      rescue StandardError => e
        # Wrap unexpected errors
        @logger.error("Hook failed unexpectedly: #{e.class} - #{e.message}")
        @logger.error(e.backtrace.join("\n"))
        raise Error.new(
          "Hook failed: #{e.message}",
          context: context,
        )
      end

      # Execute a single hook
      #
      # @param hook_def [Definition] Hook to execute
      # @param context [Context] Current context
      # @return [Result, nil] Result from hook (Result or nil)
      # @raise [Error] If hook execution fails
      def execute_single(hook_def, context)
        proc = hook_def.resolve_proc(@registry)

        @logger.debug("Executing hook for #{context.event} (agent: #{context.agent_name})")

        # Execute hook with context as parameter
        # Users can access convenience methods via context parameter:
        #   hook(:event) { |ctx| ctx.halt("msg") }
        # This preserves lexical scope and access to surrounding instance variables
        proc.call(context)
      rescue Error
        # Pass through blocking errors
        raise
      rescue StandardError => e
        # Wrap other errors with context and detailed debugging
        hook_name = hook_def.named_hook? ? hook_def.proc : "anonymous"

        # Log detailed error info for debugging
        @logger.error("=" * 80)
        @logger.error("HOOK EXECUTION ERROR")
        @logger.error("  Hook: #{hook_name}")
        @logger.error("  Event: #{context.event}")
        @logger.error("  Agent: #{context.agent_name}")
        @logger.error("  Proc class: #{proc.class}")
        @logger.error("  Proc arity: #{proc.arity} (expected: 1 for |context|)")
        @logger.error("  Error: #{e.class.name}: #{e.message}")
        @logger.error("  Backtrace:")
        e.backtrace.first(15).each { |line| @logger.error("    #{line}") }
        @logger.error("=" * 80)

        raise Error.new(
          "Hook #{hook_name} failed: #{e.message}",
          hook_name: hook_name,
          context: context,
        )
      end

      # Execute hooks and return result safely (without raising)
      #
      # This is a convenience method that catches Error and converts it
      # to a halt result, making it easier to use in control flow.
      #
      # @param event [Symbol] Event type
      # @param context [Context] Context to pass to hooks
      # @param callbacks [Array<Definition>] Agent-specific hooks
      # @return [Result] Result from hooks
      def execute_safe(event:, context:, callbacks: [])
        execute(event: event, context: context, callbacks: callbacks)
      rescue Error => e
        @logger.warn("Execution blocked by hook: #{e.message}")
        Result.halt(e.message)
      end
    end
  end
end
