# frozen_string_literal: true

require "test_helper"

class ProvidersResponseNormalizerTest < Minitest::Test
  def setup
    skip_unless_ruby_llm_available
  end

  def test_normalize_with_complete_response
    response = MockResponse.new(
      content: "This is the response content",
      input_tokens: 100,
      output_tokens: 50
    )

    normalized = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "openai",
      response: response,
      duration_ms: 1500,
      session_id: "test-session-123"
    )

    assert_equal "result", normalized["type"]
    assert_equal "This is the response content", normalized["result"]
    assert_equal 1500, normalized["duration_ms"]
    assert_equal "test-session-123", normalized["session_id"]
    assert_kind_of Hash, normalized["usage"]
    assert_equal 100, normalized["usage"]["input_tokens"]
    assert_equal 50, normalized["usage"]["output_tokens"]
    assert_kind_of Float, normalized["total_cost"]
  end

  def test_normalize_with_missing_tokens
    response = MockResponse.new(
      content: "Response without token counts",
      input_tokens: nil,
      output_tokens: nil
    )

    normalized = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "google",
      response: response,
      duration_ms: 800,
      session_id: "session-456"
    )

    assert_equal 0, normalized["usage"]["input_tokens"]
    assert_equal 0, normalized["usage"]["output_tokens"]
    assert_in_delta(0.0, normalized["total_cost"])
  end

  def test_extract_content_from_content_method
    response = MockResponse.new(content: "Content from method")

    content = ClaudeSwarm::Providers::ResponseNormalizer.extract_content(response)

    assert_equal "Content from method", content
  end

  def test_extract_content_from_text_method
    response = MockTextResponse.new(text: "Text from method")

    content = ClaudeSwarm::Providers::ResponseNormalizer.extract_content(response)

    assert_equal "Text from method", content
  end

  def test_extract_content_from_message_method
    response = MockMessageResponse.new(message: "Message from method")

    content = ClaudeSwarm::Providers::ResponseNormalizer.extract_content(response)

    assert_equal "Message from method", content
  end

  def test_extract_content_from_hash
    response = { "content" => "Content from hash" }

    content = ClaudeSwarm::Providers::ResponseNormalizer.extract_content(response)

    assert_equal "Content from hash", content
  end

  def test_extract_content_from_hash_with_text_key
    response = { "text" => "Text from hash" }

    content = ClaudeSwarm::Providers::ResponseNormalizer.extract_content(response)

    assert_equal "Text from hash", content
  end

  def test_extract_content_fallback_to_string
    response = "Plain string response"

    content = ClaudeSwarm::Providers::ResponseNormalizer.extract_content(response)

    assert_equal "Plain string response", content
  end

  def test_calculate_cost_for_openai
    response = MockResponse.new(input_tokens: 1000, output_tokens: 2000)

    normalized = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "openai",
      response: response,
      duration_ms: 1000,
      session_id: "test"
    )

    # 1000 * 0.00001 + 2000 * 0.00003 = 0.01 + 0.06 = 0.07
    assert_in_delta(0.07, normalized["total_cost"])
  end

  def test_calculate_cost_for_google
    response = MockResponse.new(input_tokens: 1000, output_tokens: 2000)

    normalized = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "google",
      response: response,
      duration_ms: 1000,
      session_id: "test"
    )

    # 1000 * 0.0000005 + 2000 * 0.0000015 = 0.0005 + 0.003 = 0.0035
    assert_in_delta(0.0035, normalized["total_cost"])
  end

  def test_calculate_cost_for_anthropic
    response = MockResponse.new(input_tokens: 1000, output_tokens: 2000)

    normalized = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "anthropic",
      response: response,
      duration_ms: 1000,
      session_id: "test"
    )

    # 1000 * 0.00001 + 2000 * 0.00003 = 0.01 + 0.06 = 0.07
    assert_in_delta(0.07, normalized["total_cost"])
  end

  def test_calculate_cost_for_cohere
    response = MockResponse.new(input_tokens: 1000, output_tokens: 2000)

    normalized = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "cohere",
      response: response,
      duration_ms: 1000,
      session_id: "test"
    )

    # 1000 * 0.000001 + 2000 * 0.000002 = 0.001 + 0.004 = 0.005
    assert_in_delta(0.005, normalized["total_cost"])
  end

  def test_calculate_cost_for_unknown_provider
    response = MockResponse.new(input_tokens: 1000, output_tokens: 2000)

    normalized = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "unknown",
      response: response,
      duration_ms: 1000,
      session_id: "test"
    )

    assert_in_delta(0.0, normalized["total_cost"])
  end

  def test_cost_calculation_rounds_to_5_decimals
    response = MockResponse.new(input_tokens: 333, output_tokens: 777)

    normalized = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "openai",
      response: response,
      duration_ms: 1000,
      session_id: "test"
    )

    # 333 * 0.00001 + 777 * 0.00003 = 0.00333 + 0.02331 = 0.02664
    assert_in_delta(0.02664, normalized["total_cost"])
  end

  def test_normalize_preserves_all_required_fields
    response = MockResponse.new(
      content: "Test",
      input_tokens: 10,
      output_tokens: 20
    )

    normalized = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "openai",
      response: response,
      duration_ms: 500,
      session_id: "abc123"
    )

    # Ensure all required fields are present
    assert normalized.key?("type")
    assert normalized.key?("result")
    assert normalized.key?("duration_ms")
    assert normalized.key?("total_cost")
    assert normalized.key?("session_id")
    assert normalized.key?("usage")
    assert normalized["usage"].key?("input_tokens")
    assert normalized["usage"].key?("output_tokens")
  end

  def test_provider_name_is_case_insensitive
    response = MockResponse.new(input_tokens: 1000, output_tokens: 1000)

    normalized_lower = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "openai",
      response: response,
      duration_ms: 100,
      session_id: "test"
    )

    normalized_upper = ClaudeSwarm::Providers::ResponseNormalizer.normalize(
      provider: "OPENAI",
      response: response,
      duration_ms: 100,
      session_id: "test"
    )

    assert_equal normalized_lower["total_cost"], normalized_upper["total_cost"]
  end

  # Mock response classes for testing
  class MockResponse
    attr_reader :content, :input_tokens, :output_tokens

    def initialize(content: nil, input_tokens: nil, output_tokens: nil)
      @content = content
      @input_tokens = input_tokens
      @output_tokens = output_tokens
    end
  end

  class MockTextResponse
    attr_reader :text

    def initialize(text:)
      @text = text
    end
  end

  class MockMessageResponse
    attr_reader :message

    def initialize(message:)
      @message = message
    end
  end
end
