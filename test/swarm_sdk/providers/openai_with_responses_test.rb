# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Providers
    class OpenAIWithResponsesTest < Minitest::Test
      def setup
        @config = RubyLLM::Configuration.new
        @config.openai_api_key = "test-key"
        @config.openai_api_base = "https://test.api"
      end

      def test_initialization_without_explicit_use_responses_api
        provider = OpenAIWithResponses.new(@config)

        assert_nil(provider.use_responses_api)
      end

      def test_initialization_with_explicit_use_responses_api_true
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        assert(provider.use_responses_api)
      end

      def test_initialization_with_explicit_use_responses_api_false
        provider = OpenAIWithResponses.new(@config, use_responses_api: false)

        refute(provider.use_responses_api)
      end

      def test_completion_url_returns_responses_when_explicit_true
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        assert_equal("responses", provider.completion_url)
      end

      def test_completion_url_returns_chat_completions_when_explicit_false
        provider = OpenAIWithResponses.new(@config, use_responses_api: false)

        assert_equal("chat/completions", provider.completion_url)
      end

      def test_completion_url_uses_chat_completions_by_default
        provider = OpenAIWithResponses.new(@config)

        # Without explicit configuration, defaults to chat/completions
        assert_equal("chat/completions", provider.completion_url)
      end

      def test_stream_url_matches_completion_url
        provider = OpenAIWithResponses.new(@config, use_responses_api: true)

        assert_equal(provider.completion_url, provider.stream_url)
      end
    end
  end
end
