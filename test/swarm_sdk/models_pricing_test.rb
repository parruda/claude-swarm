# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ModelsPricingTest < Minitest::Test
    def test_swarm_sdk_models_have_pricing_info
      # Verify SwarmSDK::Models.find returns models with pricing
      model = SwarmSDK::Models.find("claude-sonnet-4-5-20250929")

      assert(model, "Model should exist in SwarmSDK registry")
      assert(model["pricing"], "Model should have pricing structure")

      pricing = model["pricing"]["text_tokens"]["standard"]

      assert_in_delta(3.0, pricing["input_per_million"])
      assert_in_delta(15.0, pricing["output_per_million"])
    end

    def test_gpt5_model_has_pricing
      model = SwarmSDK::Models.find("gpt-5")

      assert(model, "GPT-5 should exist in registry")
      assert(model["pricing"], "GPT-5 should have pricing")

      pricing = model["pricing"]["text_tokens"]["standard"]

      assert_in_delta(1.25, pricing["input_per_million"])
      assert_in_delta(10.0, pricing["output_per_million"])
    end

    def test_model_alias_resolution
      # Test that aliases resolve to actual models
      resolved = SwarmSDK::Models.resolve_alias("sonnet")

      # Should resolve to an actual model ID
      assert_kind_of(String, resolved)

      # Resolved model should exist in registry
      if resolved != "sonnet"
        model = SwarmSDK::Models.find(resolved)

        assert(model, "Resolved model should exist in registry")
      end
    end

    def test_unknown_model_returns_nil
      model = SwarmSDK::Models.find("completely-unknown-model-xyz-123")

      assert_nil(model, "Unknown model should return nil")
    end

    def test_pricing_structure_consistency
      # Verify multiple models in registry have pricing
      models_with_pricing = SwarmSDK::Models.all.select do |m|
        pricing = m["pricing"] || m[:pricing]
        pricing && pricing["text_tokens"] && pricing["text_tokens"]["standard"]
      end

      # Should have multiple models with pricing
      assert_operator(models_with_pricing.count, :>, 10, "Should have multiple models with pricing")

      # Spot check a few
      claude = models_with_pricing.find { |m| m["id"] =~ /claude-sonnet-4-5/ }

      assert(claude, "Should have Claude Sonnet 4.5 with pricing")

      gpt5 = models_with_pricing.find { |m| m["id"] == "gpt-5" }

      assert(gpt5, "Should have GPT-5 with pricing")
    end

    def test_pricing_calculation_example
      # Demonstrate how cost calculation works with SwarmSDK models
      model = SwarmSDK::Models.find("claude-sonnet-4-5-20250929")
      pricing = model["pricing"]["text_tokens"]["standard"]

      # Example: 1000 input tokens, 500 output tokens
      input_tokens = 1000
      output_tokens = 500

      input_cost = (input_tokens / 1_000_000.0) * pricing["input_per_million"]
      output_cost = (output_tokens / 1_000_000.0) * pricing["output_per_million"]
      total_cost = input_cost + output_cost

      # 1000 input * $3/1M = $0.003
      # 500 output * $15/1M = $0.0075
      # Total = $0.0105
      assert_in_delta(0.003, input_cost, 0.0001)
      assert_in_delta(0.0075, output_cost, 0.0001)
      assert_in_delta(0.0105, total_cost, 0.0001)
    end
  end
end
