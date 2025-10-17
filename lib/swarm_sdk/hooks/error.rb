# frozen_string_literal: true

module SwarmSDK
  module Hooks
    # Error raised by callbacks to block execution
    #
    # This error provides context about which hook failed and includes
    # the execution context for debugging and error handling.
    #
    # @example Raise a hook error to block execution
    #   raise SwarmSDK::Hooks::Error.new(
    #     "Validation failed: invalid syntax",
    #     hook_name: :validate_code,
    #     context: context
    #   )
    class Error < StandardError
      attr_reader :hook_name, :context

      # @param message [String] Error message
      # @param hook_name [Symbol, String, nil] Name of the hook that failed
      # @param context [Context, nil] Execution context when error occurred
      def initialize(message, hook_name: nil, context: nil)
        super(message)
        @hook_name = hook_name
        @context = context
      end
    end
  end
end
