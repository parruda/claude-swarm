# frozen_string_literal: true

module SwarmCLI
  module UI
    # Icon definitions for terminal UI
    # Centralized so all components use the same icons
    module Icons
      # Event type icons
      THINKING = "💭"
      RESPONSE = "💬"
      SUCCESS = "✓"
      ERROR = "✗"
      INFO = "ℹ"
      WARNING = "⚠️"

      # Entity icons
      AGENT = "🤖"
      TOOL = "🔧"
      DELEGATE = "📨"
      RESULT = "📥"
      HOOK = "🪝"

      # Metric icons
      LLM = "🧠"
      TOKENS = "📊"
      COST = "💰"
      TIME = "⏱"

      # Visual elements
      SPARKLES = "✨"
      ARROW_RIGHT = "→"
      BULLET = "•"
      COMPRESS = "🗜️"

      # All icons as hash for backward compatibility
      ALL = {
        thinking: THINKING,
        response: RESPONSE,
        success: SUCCESS,
        error: ERROR,
        info: INFO,
        warning: WARNING,
        agent: AGENT,
        tool: TOOL,
        delegate: DELEGATE,
        result: RESULT,
        hook: HOOK,
        llm: LLM,
        tokens: TOKENS,
        cost: COST,
        time: TIME,
        sparkles: SPARKLES,
        arrow_right: ARROW_RIGHT,
        bullet: BULLET,
        compress: COMPRESS,
      }.freeze
    end
  end
end
