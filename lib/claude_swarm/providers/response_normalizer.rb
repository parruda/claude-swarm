# frozen_string_literal: true

module ClaudeSwarm
  module Providers
    # Normalizes responses from different LLM providers into a consistent format
    # that matches Claude's response structure
    module ResponseNormalizer
      # Normalize a provider response into Claude's format
      #
      # @param provider [String] The provider name (e.g., "openai", "google")
      # @param response [Object] The raw response from the provider
      # @param duration_ms [Integer] The duration of the request in milliseconds
      # @param session_id [String] The session ID for this conversation
      # @return [Hash] A normalized response in Claude's format
      def self.normalize(provider:, response:, duration_ms:, session_id:)
        {
          "type" => "result",
          "result" => extract_content(response),
          "duration_ms" => duration_ms,
          "total_cost" => calculate_provider_cost(provider, response),
          "session_id" => session_id,
          "usage" => {
            "input_tokens" => response.input_tokens || 0,
            "output_tokens" => response.output_tokens || 0
          }
        }
      end

      # Extract the content/result from the provider response
      #
      # @param response [Object] The provider response
      # @return [String] The extracted content
      def self.extract_content(response)
        # Handle different response structures
        if response.respond_to?(:content)
          response.content
        elsif response.respond_to?(:text)
          response.text
        elsif response.respond_to?(:message)
          response.message
        elsif response.is_a?(Hash)
          response["content"] || response["text"] || response["message"] || response.to_s
        else
          response.to_s
        end
      end

      # Calculate the cost for a provider response
      #
      # @param provider [String] The provider name
      # @param response [Object] The provider response
      # @return [Float] The calculated cost rounded to 5 decimal places
      def self.calculate_provider_cost(provider, response)
        input_tokens = response.input_tokens || 0
        output_tokens = response.output_tokens || 0

        # Provider-specific pricing (prices per 1K tokens)
        # These are example prices and should be updated with actual current pricing
        case provider.to_s.downcase
        when "openai", "anthropic"
          # GPT-4 Turbo and Claude pricing (as of plan date)
          input_cost = input_tokens * 0.00001 # $0.01 per 1K tokens
          output_cost = output_tokens * 0.00003 # $0.03 per 1K tokens
        when "google", "gemini"
          # Gemini Pro pricing (as of plan date)
          input_cost = input_tokens * 0.0000005 # $0.0005 per 1K tokens
          output_cost = output_tokens * 0.0000015 # $0.0015 per 1K tokens
        when "cohere"
          # Cohere Command pricing (as of plan date)
          input_cost = input_tokens * 0.000001 # $0.001 per 1K tokens
          output_cost = output_tokens * 0.000002 # $0.002 per 1K tokens
        else
          # Unknown provider - return 0 cost
          input_cost = 0
          output_cost = 0
        end

        (input_cost + output_cost).round(5)
      end

      private_class_method :calculate_provider_cost
    end
  end
end
