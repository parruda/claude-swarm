# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"

module SwarmSDK
  module Tools
    class WebFetchTest < Minitest::Test
      def setup
        # Configure WebFetch with LLM processing enabled for most tests
        SwarmSDK.configure do |config|
          config.webfetch_provider = "anthropic"
          config.webfetch_model = "claude-3-5-haiku-20241022"
          config.webfetch_max_tokens = 4096
        end

        @tool = WebFetch.new
        WebMock.disable_net_connect!
      end

      def teardown
        WebMock.reset!
        WebMock.allow_net_connect!
        SwarmSDK.reset_configuration!
      end

      def test_web_fetch_tool_validates_url_required
        result = @tool.execute(url: "", prompt: "What is this about?")

        assert_includes(result, "InputValidationError")
        assert_includes(result, "url is required")
      end

      def test_web_fetch_tool_with_empty_prompt_when_llm_enabled
        # With LLM enabled and empty prompt, should get validation error
        result = @tool.execute(url: "https://example.com", prompt: "")

        assert_includes(result, "InputValidationError")
        assert_includes(result, "prompt is required when LLM processing is configured")
      end

      def test_web_fetch_with_llm_enabled_requires_prompt_when_nil
        # With LLM enabled and nil prompt, should get validation error
        result = @tool.execute(url: "https://example.com")

        assert_includes(result, "InputValidationError")
        assert_includes(result, "prompt is required when LLM processing is configured")
      end

      def test_web_fetch_tool_validates_url_format
        result = @tool.execute(url: "not-a-valid-url", prompt: "What is this?")

        assert_includes(result, "InputValidationError")
        assert_includes(result, "Invalid URL format")
      end

      def test_web_fetch_tool_upgrades_http_to_https
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><body><h1>Test</h1></body></html>")

        stub_llm_response("This is a test page") do
          result = @tool.execute(url: "http://example.com", prompt: "What is this?")

          refute_includes(result, "Error")
          assert_includes(result, "test page")
        end
      end

      def test_web_fetch_tool_successful_fetch
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><body><h1>Example Title</h1></body></html>")

        stub_llm_response("This page is about examples") do
          result = @tool.execute(url: "https://example.com", prompt: "What is this page about?")

          refute_includes(result, "Error")
          assert_includes(result, "examples")
        end
      end

      def test_web_fetch_tool_handles_http_errors
        stub_request(:get, "https://example.com")
          .to_return(status: 404)

        result = @tool.execute(url: "https://example.com", prompt: "What is this?")

        assert_includes(result, "Error")
        assert_includes(result, "HTTP 404")
      end

      def test_web_fetch_tool_handles_timeout
        stub_request(:get, "https://example.com")
          .to_timeout

        result = @tool.execute(url: "https://example.com", prompt: "What is this?")

        assert_includes(result, "Error")
        # WebMock timeout raises ConnectionFailed with "execution expired" message
        assert(result.include?("Connection failed") || result.include?("timed out"))
      end

      def test_web_fetch_tool_handles_connection_failure
        stub_request(:get, "https://example.com")
          .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

        result = @tool.execute(url: "https://example.com", prompt: "What is this?")

        assert_includes(result, "Error")
        assert_includes(result, "Connection failed")
      end

      def test_web_fetch_tool_converts_html_to_markdown
        html = <<~HTML
          <html><body>
            <h1>Main Title</h1>
            <h2>Subtitle</h2>
            <p>This is a <strong>bold</strong> paragraph.</p>
          </body></html>
        HTML

        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: html)

        stub_llm_response("Converted markdown content") do
          result = @tool.execute(url: "https://example.com", prompt: "Summarize this")

          refute_includes(result, "Error")
          assert_includes(result, "Converted markdown")
        end
      end

      def test_web_fetch_tool_detects_redirect_different_host
        stub_request(:get, "https://example.com")
          .to_return(status: 301, headers: { "Location" => "https://other-site.com/page" })

        stub_request(:get, "https://other-site.com/page")
          .to_return(status: 200, body: "<html><body>Redirected</body></html>")

        result = @tool.execute(url: "https://example.com", prompt: "What is this?")

        assert_includes(result, "redirected to a different host")
        assert_includes(result, "https://other-site.com/page")
        assert_includes(result, "<system-reminder>")
      end

      def test_web_fetch_tool_caching
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><body><h1>Cached Content</h1></body></html>")
          .times(1) # Should only be called once

        stub_llm_response("This is cached content") do
          # First call should fetch and cache
          result1 = @tool.execute(url: "https://example.com", prompt: "What is this?")

          assert_includes(result1, "cached")

          # Second call with same URL and prompt should return cached result
          result2 = @tool.execute(url: "https://example.com", prompt: "What is this?")

          assert_equal(result1, result2)
        end
      end

      def test_web_fetch_tool_cache_different_prompts
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><body><h1>Content</h1></body></html>")
          .times(2) # Should be called twice for different prompts

        # First prompt
        stub_llm_response("Response 1") do
          result1 = @tool.execute(url: "https://example.com", prompt: "Question 1")

          assert_includes(result1, "Response 1")
        end

        # Second prompt - should make new request
        stub_llm_response("Response 2") do
          result2 = @tool.execute(url: "https://example.com", prompt: "Question 2")

          assert_includes(result2, "Response 2")
        end
      end

      def test_web_fetch_tool_truncates_large_content
        large_html = "<html><body><p>#{"x" * 150_000}</p></body></html>"
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: large_html)

        stub_llm_response("Summarized large content") do
          result = @tool.execute(url: "https://example.com", prompt: "What is this?")

          refute_includes(result, "Error")
          assert_includes(result, "Summarized")
        end
      end

      def test_web_fetch_without_llm_processing
        # Reset configuration to disable LLM processing
        SwarmSDK.reset_configuration!
        tool = WebFetch.new

        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><body><h1>Title</h1><p>Content</p></body></html>")

        # Should return raw markdown without prompt parameter
        result = tool.execute(url: "https://example.com")

        refute_includes(result, "Error")
        assert_includes(result, "# Title")
        assert_includes(result, "Content")
      end

      def test_web_fetch_without_llm_processing_ignores_prompt
        # Reset configuration to disable LLM processing
        SwarmSDK.reset_configuration!
        tool = WebFetch.new

        # Prompt parameter is always present but ignored when LLM is disabled
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "<html><body><h1>Test</h1></body></html>")

        result = tool.execute(url: "https://example.com", prompt: "ignored prompt")

        # Should still work, just ignore the prompt and return markdown
        refute_includes(result, "Error")
        assert_includes(result, "# Test")
      end

      def test_web_fetch_with_llm_enabled_requires_prompt
        WebFetch.new

        # With LLM enabled, prompt is a required parameter
        # RubyLLM will enforce this at the parameter level
        # So we test that we can't call it without prompt when LLM is enabled
        # This is enforced by the param definition, not by execute() logic
      end

      private

      def stub_llm_response(response_text, &block)
        # Create a mock response object
        response_mock = Minitest::Mock.new
        response_mock.expect(:content, response_text)

        # Create a mock chat object that returns itself for chaining
        chat_mock = Minitest::Mock.new
        chat_mock.expect(:with_params, chat_mock) { |args| args.is_a?(Hash) }
        chat_mock.expect(:ask, response_mock) { |prompt| prompt.is_a?(String) }

        # Stub RubyLLM.chat to return our mock chat
        RubyLLM.stub(:chat, chat_mock, &block)
      end
    end
  end
end
