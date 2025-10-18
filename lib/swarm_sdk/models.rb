# frozen_string_literal: true

module SwarmSDK
  # Models provides model validation and suggestion functionality
  #
  # Uses static JSON files:
  # - models.json: Curated model list from Parsera
  # - model_aliases.json: Shortcuts mapping to latest models
  #
  # This avoids network calls, API key requirements, and RubyLLM
  # registry manipulation.
  #
  # @example
  #   model = SwarmSDK::Models.find("claude-sonnet-4-5-20250929")
  #   model = SwarmSDK::Models.find("sonnet")  # Uses alias
  #   suggestions = SwarmSDK::Models.suggest_similar("anthropic:claude-sonnet-4-5")
  class Models
    MODELS_JSON_PATH = File.expand_path("models.json", __dir__)
    ALIASES_JSON_PATH = File.expand_path("model_aliases.json", __dir__)

    class << self
      # Find a model by ID or alias
      #
      # @param model_id [String] Model ID or alias to find
      # @return [Hash, nil] Model data or nil if not found
      def find(model_id)
        # Check if it's an alias first
        resolved_id = resolve_alias(model_id)

        all.find { |m| m["id"] == resolved_id || m[:id] == resolved_id }
      end

      # Resolve a model alias to full model ID
      #
      # @param model_id [String] Model ID or alias
      # @return [String] Resolved model ID (or original if not an alias)
      def resolve_alias(model_id)
        aliases[model_id.to_s] || model_id
      end

      # Suggest similar models for a given query
      #
      # Strips provider prefixes and normalizes for fuzzy matching.
      #
      # @param query [String] Model ID to match against
      # @param limit [Integer] Maximum number of suggestions
      # @return [Array<Hash>] Up to `limit` similar models
      def suggest_similar(query, limit: 3)
        # Strip provider prefix (e.g., "anthropic:claude-sonnet-4-5" → "claude-sonnet-4-5")
        query_without_prefix = query.to_s.sub(/^[^:]+:/, "")
        normalized_query = query_without_prefix.downcase.gsub(/[.\-_]/, "")

        matches = all.select do |model|
          model_id = (model["id"] || model[:id]).to_s
          model_name = (model["name"] || model[:name]).to_s

          normalized_id = model_id.downcase.gsub(/[.\-_]/, "")
          normalized_name = model_name.downcase.gsub(/[.\-_]/, "")

          normalized_id.include?(normalized_query) || normalized_name.include?(normalized_query)
        end.first(limit)

        matches.map do |m|
          {
            id: m["id"] || m[:id],
            name: m["name"] || m[:name],
            context_window: m["context_window"] || m[:context_window],
          }
        end
      end

      # Get all models
      #
      # @return [Array<Hash>] All models from models.json
      def all
        @models ||= load_models
      end

      # Get all aliases
      #
      # @return [Hash] Alias mappings
      def aliases
        @aliases ||= load_aliases
      end

      # Reload models and aliases from JSON files
      #
      # @return [Array<Hash>] Loaded models
      def reload!
        @models = load_models
        @aliases = load_aliases
        @models
      end

      private

      # Load models from JSON file
      #
      # @return [Array<Hash>] Models array
      def load_models
        JSON.parse(File.read(MODELS_JSON_PATH))
      rescue StandardError => e
        # Log error and return empty array
        RubyLLM.logger.error("Failed to load SwarmSDK models.json: #{e.class} - #{e.message}")
        []
      end

      # Load aliases from JSON file
      #
      # @return [Hash] Alias mappings
      def load_aliases
        JSON.parse(File.read(ALIASES_JSON_PATH))
      rescue StandardError => e
        # Log error and return empty hash
        RubyLLM.logger.debug("Failed to load SwarmSDK model_aliases.json: #{e.class} - #{e.message}")
        {}
      end
    end
  end
end
