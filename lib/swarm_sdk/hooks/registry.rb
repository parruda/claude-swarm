# frozen_string_literal: true

module SwarmSDK
  module Hooks
    # Central registry for managing named hooks and swarm-level defaults
    #
    # The Registry stores:
    # - Named hooks that can be referenced by symbol in YAML or code
    # - Swarm-level default hooks that apply to all agents
    #
    # @example Register a named hook
    #   registry = SwarmSDK::Hooks::Registry.new
    #   registry.register(:validate_code) do |context|
    #     raise SwarmSDK::Hooks::Error, "Invalid code" unless valid?(context.tool_call)
    #   end
    #
    # @example Add swarm-level default
    #   registry.add_default(:pre_tool_use, matcher: "Write|Edit") do |context|
    #     puts "Tool #{context.tool_call.name} called by #{context.agent_name}"
    #   end
    class Registry
      # Available hook event types
      VALID_EVENTS = [
        # Swarm lifecycle events
        :swarm_start,       # When Swarm.execute is called (before first user message)
        :swarm_stop,        # When Swarm.execute completes (after execution)
        :first_message,     # When first user message is sent to swarm (Swarm.execute)

        # Agent/LLM events
        :user_prompt,       # Before sending user message to LLM
        :agent_step,        # After agent makes intermediate response with tool calls
        :agent_stop,        # After agent completes with final response (no more tool calls)

        # Tool events
        :pre_tool_use,      # Before tool execution (can block/modify)
        :post_tool_use,     # After tool execution

        # Delegation events
        :pre_delegation,    # Before delegating to another agent
        :post_delegation,   # After delegation completes

        # Context events
        :context_warning, # When context usage crosses threshold

        # Debug events
        :breakpoint_enter,  # When entering interactive debugging (binding.irb)
        :breakpoint_exit,   # When exiting interactive debugging
      ].freeze

      def initialize
        @named_hooks = {} # { hook_name: proc }
        @defaults = Hash.new { |h, k| h[k] = [] } # { event_type: [Definition, ...] }
      end

      # Register a named hook that can be referenced elsewhere
      #
      # @param name [Symbol] Unique name for this hook
      # @param block [Proc] Hook implementation
      # @raise [ArgumentError] if name already registered or invalid
      #
      # @example
      #   registry.register(:log_tool_use) { |ctx| puts "Tool: #{ctx.tool_call.name}" }
      def register(name, &block)
        raise ArgumentError, "Hook name must be a symbol" unless name.is_a?(Symbol)
        raise ArgumentError, "Hook #{name} already registered" if @named_hooks.key?(name)
        raise ArgumentError, "Block required" unless block

        @named_hooks[name] = block
      end

      # Get a named hook by symbol
      #
      # @param name [Symbol] Hook name
      # @return [Proc, nil] The hook proc or nil if not found
      def get(name)
        @named_hooks[name]
      end

      # Add a swarm-level default hook
      #
      # These hooks apply to all agents unless overridden at agent level.
      #
      # @param event [Symbol] Event type (must be in VALID_EVENTS)
      # @param matcher [String, Regexp, nil] Optional regex pattern to match tool names
      # @param priority [Integer] Execution priority (higher runs first)
      # @param block [Proc] Hook implementation
      # @raise [ArgumentError] if event invalid or block missing
      #
      # @example Add default logging
      #   registry.add_default(:pre_tool_use) { |ctx| log(ctx) }
      #
      # @example Add validation for specific tools
      #   registry.add_default(:pre_tool_use, matcher: "Write|Edit") do |ctx|
      #     validate_tool_call(ctx.tool_call)
      #   end
      def add_default(event, matcher: nil, priority: 0, &block)
        validate_event!(event)
        raise ArgumentError, "Block required" unless block

        definition = Definition.new(
          event: event,
          matcher: matcher,
          priority: priority,
          proc: block,
        )

        @defaults[event] << definition
        @defaults[event].sort_by! { |d| -d.priority } # Higher priority first
      end

      # Get all default hooks for an event type
      #
      # @param event [Symbol] Event type
      # @return [Array<Definition>] List of hook definitions
      def get_defaults(event)
        @defaults[event]
      end

      # Get all registered named hook names
      #
      # @return [Array<Symbol>] List of hook names
      def named_hooks
        @named_hooks.keys
      end

      # Check if a hook name is registered
      #
      # @param name [Symbol] Hook name
      # @return [Boolean] true if registered
      def registered?(name)
        @named_hooks.key?(name)
      end

      private

      # Validate event type
      #
      # @param event [Symbol] Event to validate
      # @raise [ArgumentError] if event invalid
      def validate_event!(event)
        return if VALID_EVENTS.include?(event)

        raise ArgumentError, "Invalid event type: #{event}. Valid types: #{VALID_EVENTS.join(", ")}"
      end
    end
  end
end
