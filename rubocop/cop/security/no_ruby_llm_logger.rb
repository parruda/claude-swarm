# frozen_string_literal: true

# rubocop/no_ruby_llm_logger.rb

require "rubocop"

module RuboCop
  module Cop
    module Security
      # Custom cop to catch direct usage of RubyLLM.logger
      #
      # This cop prevents use of:
      # - RubyLLM.logger
      #
      # Direct access to RubyLLM.logger should be avoided to maintain proper
      # logging abstraction and prevent unintended side effects.
      class NoRubyLlmLogger < Base
        MSG = "Do not use `RubyLLM.logger` directly; use LogCollector instead."

        # Match method calls on RubyLLM constant
        def on_send(node)
          return unless node.receiver
          return unless node.receiver.const_type?
          return unless node.receiver.const_name == :RubyLLM
          return unless node.method_name == :logger

          add_offense(node.loc.selector, message: MSG)
        end
      end
    end
  end
end
