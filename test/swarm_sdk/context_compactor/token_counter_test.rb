# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ContextCompactor
    class TokenCounterTest < Minitest::Test
      def test_estimate_content_for_prose
        prose = "This is a simple English sentence with normal words."
        tokens = TokenCounter.estimate_content(prose)

        # Should use ~4 chars per token for prose
        expected = (prose.length / 4.0).ceil

        assert_equal(expected, tokens)
      end

      def test_estimate_content_for_code
        code = "function test() { return [1, 2, 3]; }"
        tokens = TokenCounter.estimate_content(code)

        # Should use ~3.5 chars per token for code (has brackets/braces)
        # Code ratio is high, so it should detect it as code
        expected = (code.length / 3.5).ceil

        assert_equal(expected, tokens)
      end

      def test_estimate_content_for_nil
        tokens = TokenCounter.estimate_content(nil)

        assert_equal(0, tokens)
      end

      def test_estimate_content_for_empty_string
        tokens = TokenCounter.estimate_content("")

        assert_equal(0, tokens)
      end

      def test_estimate_message_for_user_message
        message = create_message(:user, "Hello, how are you?")
        tokens = TokenCounter.estimate_message(message)

        assert_operator(tokens, :>, 0)
        assert_operator(tokens, :<, 100) # Reasonable range
      end

      def test_estimate_message_for_assistant_message
        message = create_message(:assistant, "I'm doing well, thank you!")
        tokens = TokenCounter.estimate_message(message)

        assert_operator(tokens, :>, 0)
        assert_operator(tokens, :<, 100)
      end

      def test_estimate_message_for_system_message
        message = create_message(:system, "You are a helpful assistant.")
        tokens = TokenCounter.estimate_message(message)

        assert_operator(tokens, :>, 0)
        assert_operator(tokens, :<, 100)
      end

      def test_estimate_message_for_tool_result_includes_overhead
        message = create_message(:tool, "Result: OK")
        tokens = TokenCounter.estimate_message(message)

        # Tool results have base overhead of 50 tokens
        assert_operator(tokens, :>, 50)
      end

      def test_estimate_messages_sums_all_messages
        messages = [
          create_message(:user, "Hello"),
          create_message(:assistant, "Hi there!"),
          create_message(:user, "How are you?"),
        ]

        total_tokens = TokenCounter.estimate_messages(messages)

        # Should be sum of individual estimates
        expected = messages.sum { |msg| TokenCounter.estimate_message(msg) }

        assert_equal(expected, total_tokens)
      end

      def test_estimate_messages_for_empty_array
        tokens = TokenCounter.estimate_messages([])

        assert_equal(0, tokens)
      end

      def test_detect_code_ratio_for_code
        code = "function test() { return [1, 2, 3]; }"
        ratio = TokenCounter.send(:detect_code_ratio, code)

        # Code has many brackets/braces/parens
        assert_operator(ratio, :>, 0.1)
      end

      def test_detect_code_ratio_for_prose
        prose = "This is a normal English sentence without code."
        ratio = TokenCounter.send(:detect_code_ratio, prose)

        # Prose has few code indicators
        assert_operator(ratio, :<, 0.1)
      end

      def test_detect_code_ratio_for_empty_string
        ratio = TokenCounter.send(:detect_code_ratio, "")

        assert_in_delta(0.0, ratio)
      end

      private

      # Create a mock message
      def create_message(role, content)
        msg = Object.new
        msg.define_singleton_method(:role) { role }
        msg.define_singleton_method(:content) { content }
        msg
      end
    end
  end
end
