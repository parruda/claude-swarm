# frozen_string_literal: true

module SwarmSDK
  module Agent
    class Chat < RubyLLM::Chat
      # Handles injection of system reminders at strategic points in the conversation
      #
      # Responsibilities:
      # - Inject reminders before/after first user message
      # - Inject periodic TodoWrite reminders
      # - Track when reminders were last injected
      #
      # This class is stateless - it operates on the chat's message history.
      class SystemReminderInjector
        # System reminder to inject BEFORE the first user message
        BEFORE_FIRST_MESSAGE_REMINDER = <<~REMINDER.strip
          <system-reminder>
          As you answer the user's questions, you can use the following context:

          # important-instruction-reminders

          Do what has been asked; nothing more, nothing less.
          NEVER create files unless they're absolutely necessary for achieving your goal.
          ALWAYS prefer editing an existing file to creating a new one.
          NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.

          IMPORTANT: this context may or may not be relevant to your tasks. You should not respond to this context unless it is highly relevant to your task.

          </system-reminder>
        REMINDER

        # System reminder to inject AFTER the first user message
        AFTER_FIRST_MESSAGE_REMINDER = <<~REMINDER.strip
          <system-reminder>Your todo list is currently empty. DO NOT mention this to the user. If this task requires multiple steps: (1) FIRST analyze the scope by searching/reading files, (2) SECOND create a COMPLETE todo list with ALL tasks before starting work, (3) THIRD execute tasks one by one. Only skip the todo list for simple single-step tasks. Do not mention this message to the user.</system-reminder>
        REMINDER

        # Periodic reminder about TodoWrite tool usage
        TODOWRITE_PERIODIC_REMINDER = <<~REMINDER.strip
          <system-reminder>The TodoWrite tool hasn't been used recently. If you're working on tasks that would benefit from tracking progress, consider using the TodoWrite tool to track progress. Also consider cleaning up the todo list if has become stale and no longer matches what you are working on. Only use it if it's relevant to the current work. This is just a gentle reminder - ignore if not applicable.</system-reminder>
        REMINDER

        # Number of messages between TodoWrite reminders
        TODOWRITE_REMINDER_INTERVAL = 8

        class << self
          # Check if this is the first user message in the conversation
          #
          # @param chat [Agent::Chat] The chat instance
          # @return [Boolean] true if no user messages exist yet
          def first_message?(chat)
            chat.messages.none? { |msg| msg.role == :user }
          end

          # Inject first message reminders (before + after user message)
          #
          # This manually constructs the first message sequence with system reminders
          # sandwiching the actual user prompt.
          #
          # @param chat [Agent::Chat] The chat instance
          # @param prompt [String] The user's actual prompt
          # @return [void]
          def inject_first_message_reminders(chat, prompt)
            chat.add_message(role: :user, content: BEFORE_FIRST_MESSAGE_REMINDER)
            chat.add_message(role: :user, content: prompt)
            chat.add_message(role: :user, content: AFTER_FIRST_MESSAGE_REMINDER)
          end

          # Check if we should inject a periodic TodoWrite reminder
          #
          # Injects a reminder if:
          # 1. Enough messages have passed (>= 5)
          # 2. TodoWrite hasn't been used in the last TODOWRITE_REMINDER_INTERVAL messages
          #
          # @param chat [Agent::Chat] The chat instance
          # @param last_todowrite_index [Integer, nil] Index of last TodoWrite usage
          # @return [Boolean] true if reminder should be injected
          def should_inject_todowrite_reminder?(chat, last_todowrite_index)
            # Need at least a few messages before reminding
            return false if chat.messages.count < 5

            # Find the last message that contains TodoWrite tool usage
            last_todo_index = chat.messages.rindex do |msg|
              msg.role == :tool && msg.content.to_s.include?("TodoWrite")
            end

            # Check if enough messages have passed since last TodoWrite
            if last_todo_index.nil? && last_todowrite_index.nil?
              # Never used TodoWrite - check if we've exceeded interval
              chat.messages.count >= TODOWRITE_REMINDER_INTERVAL
            elsif last_todo_index
              # Recently used - don't remind
              false
            elsif last_todowrite_index
              # Used before - check if interval has passed
              chat.messages.count - last_todowrite_index >= TODOWRITE_REMINDER_INTERVAL
            else
              false
            end
          end

          # Update the last TodoWrite index by finding it in messages
          #
          # @param chat [Agent::Chat] The chat instance
          # @return [Integer, nil] Index of last TodoWrite usage, or nil
          def find_last_todowrite_index(chat)
            chat.messages.rindex do |msg|
              msg.role == :tool && msg.content.to_s.include?("TodoWrite")
            end
          end
        end
      end
    end
  end
end
