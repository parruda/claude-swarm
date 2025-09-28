# frozen_string_literal: true

module SwarmCore
  class LLMManager
    MAX_RETRIES = 3
    RETRY_DELAYS = [1, 2, 4].freeze

    def initialize(client = nil)
      @client = client || RubyLLM
      @chat_cache = Concurrent::Hash.new
    end

    def create_chat(agent_config)
      cache_key = agent_config.name

      @chat_cache.compute_if_absent(cache_key) do
        chat = @client.chat(model: agent_config.model)

        chat = chat.with_instructions(agent_config.prompt) if agent_config.prompt
        chat = chat.with_temperature(agent_config.temperature) if agent_config.temperature
        chat = chat.with_max_tokens(agent_config.max_tokens) if agent_config.max_tokens

        chat
      end
    end

    def ask(chat, prompt, retries: 0)
      response = chat.ask(prompt)

      raise LLMError, "No response from LLM" unless response

      response
    rescue StandardError => e
      if retries < MAX_RETRIES
        sleep(RETRY_DELAYS[retries])
        ask(chat, prompt, retries: retries + 1)
      else
        raise LLMError, "LLM request failed after #{MAX_RETRIES} retries: #{e.message}"
      end
    end

    def clear_cache
      @chat_cache.clear
    end
  end
end
