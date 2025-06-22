# frozen_string_literal: true

require "test_helper"

class ProvidersCapabilitiesTest < Minitest::Test
  def setup
    skip_unless_ruby_llm_available
  end

  def test_capabilities_constant_is_frozen
    assert_predicate ClaudeSwarm::Providers::CAPABILITIES, :frozen?
  end

  def test_anthropic_capabilities
    capabilities = ClaudeSwarm::Providers::CAPABILITIES["anthropic"]

    assert capabilities[:supports_streaming]
    assert capabilities[:supports_tools]
    assert capabilities[:supports_system_prompt]
    assert_equal 200_000, capabilities[:max_context]
    assert_equal :xml, capabilities[:tool_format]
    refute capabilities[:supports_custom_base]
  end

  def test_openai_capabilities
    capabilities = ClaudeSwarm::Providers::CAPABILITIES["openai"]

    assert capabilities[:supports_streaming]
    assert capabilities[:supports_tools]
    assert capabilities[:supports_system_prompt]
    assert_equal 128_000, capabilities[:max_context]
    assert_equal :json, capabilities[:tool_format]
    assert capabilities[:supports_custom_base]
  end

  def test_google_capabilities
    capabilities = ClaudeSwarm::Providers::CAPABILITIES["google"]

    assert capabilities[:supports_streaming]
    refute capabilities[:supports_tools]
    assert capabilities[:supports_system_prompt]
    assert_equal 2_000_000, capabilities[:max_context]
    assert_nil capabilities[:tool_format]
    refute capabilities[:supports_custom_base]
  end

  def test_cohere_capabilities
    capabilities = ClaudeSwarm::Providers::CAPABILITIES["cohere"]

    assert capabilities[:supports_streaming]
    assert capabilities[:supports_tools]
    assert capabilities[:supports_system_prompt]
    assert_equal 128_000, capabilities[:max_context]
    assert_equal :json, capabilities[:tool_format]
    refute capabilities[:supports_custom_base]
  end

  def test_supports_method_with_valid_provider_and_capability
    assert ClaudeSwarm::Providers.supports?("anthropic", :supports_tools)
    refute ClaudeSwarm::Providers.supports?("google", :supports_tools)
    assert_equal 200_000, ClaudeSwarm::Providers.supports?("anthropic", :max_context)
    assert_equal :xml, ClaudeSwarm::Providers.supports?("anthropic", :tool_format)
  end

  def test_supports_method_with_string_capability
    assert ClaudeSwarm::Providers.supports?("openai", "supports_custom_base")
    assert_equal :json, ClaudeSwarm::Providers.supports?("openai", "tool_format")
  end

  def test_supports_method_with_symbol_provider
    assert ClaudeSwarm::Providers.supports?(:anthropic, :supports_streaming)
    assert_equal 128_000, ClaudeSwarm::Providers.supports?(:cohere, :max_context)
  end

  def test_supports_method_with_unknown_provider
    refute ClaudeSwarm::Providers.supports?("unknown_provider", :supports_tools)
    refute ClaudeSwarm::Providers.supports?("unknown_provider", :max_context)
  end

  def test_supports_method_with_unknown_capability
    refute ClaudeSwarm::Providers.supports?("anthropic", :unknown_capability)
    refute ClaudeSwarm::Providers.supports?("openai", :does_not_exist)
  end

  def test_all_providers_have_required_capabilities
    required_capabilities = %i[
      supports_streaming
      supports_tools
      supports_system_prompt
      max_context
      tool_format
    ]

    ClaudeSwarm::Providers::CAPABILITIES.each do |provider, capabilities|
      required_capabilities.each do |capability|
        assert capabilities.key?(capability),
               "Provider #{provider} missing required capability: #{capability}"
      end
    end
  end

  def test_max_context_values_are_positive_integers
    ClaudeSwarm::Providers::CAPABILITIES.each do |provider, capabilities|
      max_context = capabilities[:max_context]

      assert_kind_of Integer, max_context,
                     "Provider #{provider} max_context should be an Integer"
      assert_predicate max_context, :positive?,
                       "Provider #{provider} max_context should be positive"
    end
  end

  def test_tool_format_values_are_valid
    valid_formats = [:xml, :json, nil]

    ClaudeSwarm::Providers::CAPABILITIES.each do |provider, capabilities|
      tool_format = capabilities[:tool_format]

      assert_includes valid_formats, tool_format,
                      "Provider #{provider} has invalid tool_format: #{tool_format}"
    end
  end
end
