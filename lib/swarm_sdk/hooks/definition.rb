# frozen_string_literal: true

module SwarmSDK
  module Hooks
    # Represents a single hook configuration
    #
    # A hook definition includes:
    # - Event type (when to trigger)
    # - Optional matcher (regex for tool names)
    # - Priority (execution order)
    # - Proc to execute
    #
    # @example Create a hook definition
    #   definition = SwarmSDK::Hooks::Definition.new(
    #     event: :pre_tool_use,
    #     matcher: "Write|Edit",
    #     priority: 10,
    #     proc: ->(ctx) { validate_code(ctx.tool_call) }
    #   )
    class Definition
      attr_reader :event, :matcher, :priority, :proc

      # @param event [Symbol] Event type (e.g., :pre_tool_use)
      # @param matcher [String, Regexp, nil] Optional regex pattern for tool names
      # @param priority [Integer] Execution priority (higher = earlier)
      # @param proc [Proc, Symbol] Hook proc or named hook symbol
      def initialize(event:, matcher: nil, priority: 0, proc:)
        @event = event
        @matcher = compile_matcher(matcher)
        @priority = priority
        @proc = proc
      end

      # Check if this hook should execute for a given tool name
      #
      # @param tool_name [String] Name of the tool being called
      # @return [Boolean] true if hook should execute
      def matches?(tool_name)
        return true if @matcher.nil? # No matcher = matches everything

        @matcher.match?(tool_name)
      end

      # Check if this hook uses a named reference
      #
      # @return [Boolean] true if proc is a symbol (named hook)
      def named_hook?
        @proc.is_a?(Symbol)
      end

      # Resolve the actual proc, looking up named hooks if needed
      #
      # @param registry [Registry] Registry to lookup named hooks
      # @return [Proc] The actual proc to execute
      # @raise [ArgumentError] if named hook not found
      def resolve_proc(registry)
        return @proc unless named_hook?

        resolved = registry.get(@proc)
        raise ArgumentError, "Named hook :#{@proc} not found in registry" unless resolved

        resolved
      end

      private

      # Compile matcher string/regexp into regexp
      #
      # @param matcher [String, Regexp, nil] Matcher pattern
      # @return [Regexp, nil] Compiled regex or nil
      def compile_matcher(matcher)
        return if matcher.nil?
        return matcher if matcher.is_a?(Regexp)

        # Convert string to regex, treating it as a pattern with | for OR
        Regexp.new(matcher)
      end
    end
  end
end
