# frozen_string_literal: true

require "webmock"
require "securerandom"

module LLMMockHelper
  # Mock an OpenAI-style chat completion response
  #
  # @param content [String] Response text content
  # @param model [String] Model name (default: "gpt-5")
  # @param tool_calls [Array<Hash>] Optional tool calls
  # @return [Hash] OpenAI API response structure
  def mock_llm_response(content: "Mocked response", model: "gpt-5", tool_calls: nil)
    response = {
      id: "chatcmpl-#{SecureRandom.hex(12)}",
      object: "chat.completion",
      created: Time.now.to_i,
      model: model,
      choices: [
        {
          index: 0,
          message: {
            role: "assistant",
            content: content,
          },
          finish_reason: tool_calls ? "tool_calls" : "stop",
        },
      ],
      usage: {
        prompt_tokens: 10,
        completion_tokens: 20,
        total_tokens: 30,
      },
    }

    if tool_calls
      response[:choices][0][:message][:tool_calls] = tool_calls.map.with_index do |tc, _i|
        {
          id: "call_#{SecureRandom.hex(12)}",
          type: "function",
          function: {
            name: tc[:name],
            arguments: tc[:arguments].to_json,
          },
        }
      end
      response[:choices][0][:message][:content] = nil
    end

    response
  end

  # Stub OpenAI API endpoint with a response
  #
  # @param response [Hash] Response hash (use mock_llm_response to create)
  # @param times [Integer] Number of times to return this response (default: 1)
  # @param url_pattern [Regexp, String] URL pattern to match (default: OpenAI API)
  def stub_llm_request(response, times: 1, url_pattern: nil)
    url_pattern ||= %r{https?://.*/(v1/)?chat/completions}

    stub = WebMock.stub_request(:post, url_pattern)
      .to_return(
        status: 200,
        body: response.to_json,
        headers: { "Content-Type" => "application/json" },
      )

    stub.times(times) if times > 1
    stub
  end

  # Stub multiple sequential LLM responses
  #
  # Useful for testing tool call loops where the LLM:
  # 1. Makes tool calls
  # 2. Receives tool results
  # 3. Generates final response
  #
  # @param responses [Array<Hash>] Array of response hashes
  # @param url_pattern [Regexp, String] URL pattern to match
  def stub_llm_sequence(*responses, url_pattern: nil)
    url_pattern ||= %r{https?://.*/(v1/)?chat/completions}

    WebMock.stub_request(:post, url_pattern)
      .to_return(responses.map { |r| { status: 200, body: r.to_json, headers: { "Content-Type" => "application/json" } } })
  end

  # Stub LLM error response
  #
  # @param error_code [String] OpenAI error code (e.g., "rate_limit_exceeded")
  # @param message [String] Error message
  # @param status [Integer] HTTP status code (default: 429)
  # @param url_pattern [Regexp, String] URL pattern to match
  def stub_llm_error(error_code: "rate_limit_exceeded", message: "Rate limit exceeded", status: 429, url_pattern: nil)
    url_pattern ||= %r{https?://.*/(v1/)?chat/completions}

    WebMock.stub_request(:post, url_pattern)
      .to_return(
        status: status,
        body: {
          error: {
            message: message,
            type: error_code,
            code: error_code,
          },
        }.to_json,
        headers: { "Content-Type" => "application/json" },
      )
  end

  # Stub LLM timeout
  #
  # @param url_pattern [Regexp, String] URL pattern to match
  def stub_llm_timeout(url_pattern: nil)
    url_pattern ||= %r{https?://.*/(v1/)?chat/completions}

    WebMock.stub_request(:post, url_pattern)
      .to_timeout
  end

  # Stub LLM network error
  #
  # @param url_pattern [Regexp, String] URL pattern to match
  def stub_llm_network_error(url_pattern: nil)
    url_pattern ||= %r{https?://.*/(v1/)?chat/completions}

    WebMock.stub_request(:post, url_pattern)
      .to_raise(Faraday::ConnectionFailed.new("Connection refused"))
  end
end
