# frozen_string_literal: true

module SwarmSDK
  module Tools
    # Think tool for explicit reasoning and planning
    #
    # Allows the agent to write down thoughts, plans, strategies, and intermediate
    # calculations. These thoughts become part of the conversation context, enabling
    # better attention and reasoning through complex problems.
    #
    # This is inspired by research showing that explicitly articulating reasoning steps
    # (chain-of-thought prompting) leads to significantly better outcomes, especially
    # for complex tasks requiring multi-step reasoning or arithmetic.
    class Think < RubyLLM::Tool
      def name
        "Think"
      end

      description <<~DESC
        **IMPORTANT: You SHOULD use this tool frequently throughout your work. Using this tool leads to significantly
        better outcomes and more accurate solutions. Make it a habit to think before acting.**

        This tool allows you to write down your thoughts, plans, strategies, and intermediate calculations.
        Think of it as your working memory - just as humans think before speaking or acting, you should think before
        using other tools or providing responses.

        **STRONGLY RECOMMENDED to use this tool:**
        - **ALWAYS** before starting any task (even simple ones)
        - **ALWAYS** when you need to do any arithmetic or counting
        - **ALWAYS** after reading files or getting search results to process what you learned
        - **FREQUENTLY** between steps to track progress and plan next actions

        This is your private thinking space - use it liberally to enhance your problem-solving capabilities. Recording
        your thoughts helps you maintain context across multiple steps and remember important information throughout your task.

        When and how to use this tool:

        1. **Before starting any complex task**: Write down your understanding of the problem, break it into smaller
           sub-tasks, and create a step-by-step plan. Example:
           - "The user wants me to refactor this codebase. Let me first understand the structure..."
           - "I need to: 1) Analyze current architecture, 2) Identify pain points, 3) Propose changes..."

        2. **For arithmetic and calculations**: Work through math problems step by step. Example:
           - "If we have 150 requests/second and each takes 20ms, that's 150 * 0.02 = 3 seconds of CPU time..."
           - "Converting 2GB to bytes: 2 * 1024 * 1024 * 1024 = 2,147,483,648 bytes"

        3. **After completing sub-tasks**: Summarize what you've accomplished and what remains. Example:
           - "I've successfully implemented the authentication module. Next, I need to integrate it with the API..."
           - "Fixed 3 out of 5 bugs. Remaining: memory leak in parser, race condition in worker thread"

        4. **When encountering complexity**: Break down complex logic or decisions. Example:
           - "This function has multiple edge cases. Let me list them: null input, empty array, negative numbers..."
           - "The user's request is ambiguous. Possible interpretations: A) modify existing code, B) create new module..."

        5. **For remembering context**: Store important information you'll need later. Example:
           - "Important: The user mentioned they're using Ruby 3.2, so I can use pattern matching"
           - "File structure: main.rb requires from lib/, config is in config.yml"

        6. **When debugging or analyzing**: Track your investigation process. Example:
           - "The error occurs in line 42. Let me trace backwards: function called from main(), receives data from..."
           - "Hypothesis: the bug might be due to timezone differences. Let me check..."

        7. **For creative problem-solving**: Brainstorm multiple approaches before choosing one. Example:
           - "Approaches to optimize this: 1) Add caching, 2) Use parallel processing, 3) Optimize algorithm..."
           - "Design patterns that could work here: Factory, Observer, or maybe Strategy pattern..."

        **Remember: The most successful agents use this tool 5-10 times per task on average. If you haven't used this
        tool in the last 2-3 actions, you probably should. Using this tool is a sign of thoughtful, methodical problem
        solving and leads to fewer mistakes and better solutions.**

        Your thoughts persist throughout your session as part of the conversation history, so you can refer
        back to earlier thinking. Use clear formatting and organization to make it easy to reference
        later. Don't hesitate to think out loud - this tool is designed to augment your cognitive capabilities and help
        you deliver better solutions.

        **CRITICAL:** The Think tool takes only one parameter: thoughts. Do not include any other parameters.
      DESC

      param :thoughts,
        type: "string",
        desc: "Your thoughts, plans, calculations, or any notes you want to record",
        required: true

      def execute(**kwargs)
        <<~RESP
          Thought noted.
        RESP
        # <system-reminder>The user cannot see your thoughts. You MUST NOT stop without giving the user a response.</system-reminder>
      end

      private

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end
    end
  end
end
