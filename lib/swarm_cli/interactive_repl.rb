# frozen_string_literal: true

require "reline"
require "tty-spinner"
require "tty-markdown"
require "tty-box"
require "pastel"

module SwarmCLI
  # InteractiveREPL provides a professional, interactive terminal interface
  # for conversing with SwarmSDK agents.
  #
  # Features:
  # - Multiline input with intuitive submission (Enter on empty line or Ctrl+D)
  # - Beautiful Markdown rendering for agent responses
  # - Progress indicators during processing
  # - Command system (/help, /exit, /clear, etc.)
  # - Conversation history with context preservation
  # - Professional styling with Pastel and TTY tools
  #
  class InteractiveREPL
    COMMANDS = {
      "/help" => "Show available commands",
      "/clear" => "Clear the screen",
      "/history" => "Show conversation history",
      "/exit" => "Exit the REPL (or press Ctrl+D)",
    }.freeze

    def initialize(swarm:, options:, initial_message: nil)
      @swarm = swarm
      @options = options
      @initial_message = initial_message
      @conversation_history = []
      @session_results = [] # Accumulate all results for session summary
      @validation_warnings_shown = false

      setup_ui_components

      # Create formatter for swarm execution output (interactive mode)
      @formatter = Formatters::HumanFormatter.new(
        output: $stdout,
        quiet: options.quiet?,
        truncate: options.truncate?,
        verbose: options.verbose?,
        mode: :interactive,
      )
    end

    def run
      display_welcome

      # Emit validation warnings before first prompt
      emit_validation_warnings_before_prompt

      # Send initial message if provided
      if @initial_message && !@initial_message.empty?
        handle_message(@initial_message)
      end

      main_loop
      display_goodbye
      display_session_summary
    rescue Interrupt
      puts "\n"
      display_goodbye
      display_session_summary
      exit(130)
    end

    private

    def setup_ui_components
      @pastel = Pastel.new(enabled: $stdout.tty?)

      # Configure Reline for smooth, flicker-free input (like IRB)
      Reline.output = $stdout
      Reline.input = $stdin

      # Configure tab completion UI colors (Ruby 3.1+)
      configure_completion_ui

      # Enable automatic completions (show as you type)
      Reline.autocompletion = true

      # Configure word break characters
      Reline.completer_word_break_characters = " \t\n,;|&"

      # Disable default autocomplete (uses start_with? filtering)
      Reline.add_dialog_proc(:autocomplete, nil, nil)

      # Add custom fuzzy completion dialog (bypasses Reline's filtering)
      setup_fuzzy_completion

      # Rebind Tab to invoke our custom dialog (not the default :complete method)
      config = Reline.core.config
      config.add_default_key_binding_by_keymap(:emacs, [9], :fuzzy_complete)
      config.add_default_key_binding_by_keymap(:vi_insert, [9], :fuzzy_complete)

      # Setup colors using detached styles for performance
      @colors = {
        prompt: @pastel.bright_cyan.bold.detach,
        user_input: @pastel.white.detach,
        agent_text: @pastel.bright_white.detach,
        agent_label: @pastel.bright_blue.bold.detach,
        success: @pastel.bright_green.detach,
        success_icon: @pastel.bright_green.bold.detach,
        error: @pastel.bright_red.detach,
        error_icon: @pastel.bright_red.bold.detach,
        warning: @pastel.bright_yellow.detach,
        system: @pastel.dim.detach,
        system_bracket: @pastel.bright_black.detach,
        divider: @pastel.bright_black.detach,
        header: @pastel.bright_cyan.bold.detach,
        code: @pastel.bright_magenta.detach,
      }
    end

    def display_welcome
      divider = @colors[:divider].call("─" * 60)

      puts ""
      puts divider
      puts @colors[:header].call("🚀 Swarm CLI Interactive REPL")
      puts divider
      puts ""
      puts @colors[:agent_text].call("Swarm: #{@swarm.name}")
      puts @colors[:system].call("Lead Agent: #{@swarm.lead_agent}")
      puts ""
      puts @colors[:system].call("Type your message and press Enter to submit")
      puts @colors[:system].call("Type #{@colors[:code].call("/help")} for commands or #{@colors[:code].call("/exit")} to quit")
      puts ""
      puts divider
      puts ""
    end

    def main_loop
      catch(:exit_repl) do
        loop do
          input = read_user_input

          break if input.nil? # Ctrl+D pressed
          next if input.strip.empty?

          if input.start_with?("/")
            handle_command(input.strip)
          else
            handle_message(input)
          end

          puts "" # Spacing between interactions
        end
      end
    end

    def read_user_input
      # Display stats separately (they scroll up naturally)
      display_prompt_stats

      # Build the prompt indicator with colors
      prompt_indicator = build_prompt_indicator

      # Use Reline for flicker-free input (same as IRB)
      # Second parameter true = add to history for arrow up/down
      line = Reline.readline(prompt_indicator, true)

      return if line.nil? # Ctrl+D returns nil

      # Reline doesn't include newline, just strip whitespace
      line.strip
    end

    def display_prompt_stats
      # Only show stats if we have conversation history
      stats = build_prompt_stats
      puts stats if stats && !stats.empty?
    end

    def build_prompt_indicator
      # Reline supports ANSI colors without flickering!
      # Use your beautiful colored prompt
      @pastel.bright_cyan("You") +
        @pastel.bright_black(" ❯ ")
    end

    def build_prompt_stats
      return "" if @conversation_history.empty?

      parts = []

      # Agent name
      parts << @colors[:agent_label].call(@swarm.lead_agent.to_s)

      # Message count (user messages only)
      msg_count = @conversation_history.count { |entry| entry[:role] == "user" }
      parts << "#{msg_count} #{msg_count == 1 ? "msg" : "msgs"}"

      # Get last result stats if available
      if @last_result
        # Token count
        tokens = @last_result.total_tokens
        if tokens > 0
          formatted_tokens = format_number(tokens)
          parts << "#{formatted_tokens} tokens"
        end

        # Cost
        cost = @last_result.total_cost
        if cost > 0
          formatted_cost = format_cost_value(cost)
          parts << formatted_cost
        end

        # Context percentage (from last log entry with usage info)
        if @last_context_percentage
          color_method = context_percentage_color(@last_context_percentage)
          colored_pct = @pastel.public_send(color_method, @last_context_percentage)
          parts << "#{colored_pct} context"
        end
      end

      "[#{parts.join(" • ")}]"
    end

    def format_number(num)
      if num >= 1_000_000
        "#{(num / 1_000_000.0).round(1)}M"
      elsif num >= 1_000
        "#{(num / 1_000.0).round(1)}K"
      else
        num.to_s
      end
    end

    def format_cost_value(cost)
      if cost < 0.01
        "$#{format("%.4f", cost)}"
      elsif cost < 1.0
        "$#{format("%.3f", cost)}"
      else
        "$#{format("%.2f", cost)}"
      end
    end

    def context_percentage_color(percentage_string)
      percentage = percentage_string.to_s.gsub("%", "").to_f

      if percentage < 50
        :green
      elsif percentage < 80
        :yellow
      else
        :red
      end
    end

    def handle_command(input)
      command = input.split.first.downcase

      case command
      when "/help"
        display_help
      when "/clear"
        system("clear") || system("cls")
        display_welcome
      when "/history"
        display_history
      when "/exit"
        # Break from main loop to trigger session summary
        throw(:exit_repl)
      else
        puts render_error("Unknown command: #{command}")
        puts @colors[:system].call("Type /help for available commands")
      end
    end

    def handle_message(input)
      # Add to history
      @conversation_history << { role: "user", content: input }

      puts ""

      # Execute swarm with logging through formatter
      result = @swarm.execute(input) do |log_entry|
        # Skip model warnings - already emitted before first prompt
        next if log_entry[:type] == "model_lookup_warning"

        @formatter.on_log(log_entry)

        # Track context percentage from usage info
        if log_entry[:usage] && log_entry[:usage][:tokens_used_percentage]
          @last_context_percentage = log_entry[:usage][:tokens_used_percentage]
        end
      end

      # Check for errors
      if result.failure?
        @formatter.on_error(error: result.error, duration: result.duration)
        return
      end

      # Display success through formatter (minimal in interactive mode)
      @formatter.on_success(result: result)

      # Store result for prompt stats and session summary
      @last_result = result
      @session_results << result

      # Add response to history
      @conversation_history << { role: "agent", content: result.content }
    rescue StandardError => e
      @formatter.on_error(error: e)
    end

    def emit_validation_warnings_before_prompt
      # Setup temporary logging to capture and display warnings
      SwarmSDK::LogCollector.on_log do |log_entry|
        @formatter.on_log(log_entry) if log_entry[:type] == "model_lookup_warning"
      end

      SwarmSDK::LogStream.emitter = SwarmSDK::LogCollector

      # Emit validation warnings as log events
      @swarm.emit_validation_warnings

      # Clean up
      SwarmSDK::LogCollector.reset!
      SwarmSDK::LogStream.reset!

      # Add spacing if warnings were shown
      puts "" if @swarm.validate.any?
    rescue StandardError
      # Ignore errors during validation emission
      begin
        SwarmSDK::LogCollector.reset!
      rescue
        nil
      end
      begin
        SwarmSDK::LogStream.reset!
      rescue
        nil
      end
    end

    def display_help
      help_box = TTY::Box.frame(
        @colors[:header].call("Available Commands:"),
        "",
        *COMMANDS.map do |cmd, desc|
          cmd_styled = @colors[:code].call(cmd.ljust(15))
          desc_styled = @colors[:system].call(desc)
          "  #{cmd_styled} #{desc_styled}"
        end,
        "",
        @colors[:system].call("Input Tips:"),
        @colors[:system].call("  • Type your message and press Enter to submit"),
        @colors[:system].call("  • Press Ctrl+D to exit"),
        @colors[:system].call("  • Use arrow keys for history and editing"),
        @colors[:system].call("  • Type / for commands or @ for file paths"),
        @colors[:system].call("  • Use Shift-Tab to navigate autocomplete menu"),
        border: :light,
        padding: [1, 2],
        align: :left,
        title: { top_left: " HELP " },
        style: {
          border: { fg: :bright_yellow },
        },
      )

      puts help_box
    end

    def display_history
      if @conversation_history.empty?
        puts @colors[:system].call("No conversation history yet")
        return
      end

      puts @colors[:header].call("Conversation History:")
      puts @colors[:divider].call("─" * 60)
      puts ""

      @conversation_history.each_with_index do |entry, index|
        role_label = if entry[:role] == "user"
          @colors[:prompt].call("User")
        else
          @colors[:agent_label].call("Agent")
        end

        puts "#{index + 1}. #{role_label}:"

        # Truncate long messages in history view
        content = entry[:content]
        if content.length > 200
          content = content[0...200] + "..."
        end

        puts @colors[:system].call("   #{content.gsub("\n", "\n   ")}")
        puts ""
      end

      puts @colors[:divider].call("─" * 60)
    end

    def display_goodbye
      puts ""
      goodbye_text = @colors[:success].call("👋 Goodbye! Thanks for using Swarm CLI")
      puts goodbye_text
      puts ""
    end

    def display_session_summary
      return if @session_results.empty?

      # Calculate session totals
      total_tokens = @session_results.sum(&:total_tokens)
      total_cost = @session_results.sum(&:total_cost)
      total_llm_requests = @session_results.sum(&:llm_requests)
      total_tool_calls = @session_results.sum(&:tool_calls_count)
      all_agents = @session_results.flat_map(&:agents_involved).uniq

      # Get session duration (time from first to last message)
      session_duration = if @session_results.size > 1
        @session_results.map(&:duration).sum
      else
        @session_results.first&.duration || 0
      end

      # Render session summary
      divider = @colors[:divider].call("─" * 60)
      puts divider
      puts @colors[:header].call("📊 Session Summary")
      puts divider
      puts ""

      # Message count
      msg_count = @conversation_history.count { |entry| entry[:role] == "user" }
      puts "  #{@colors[:agent_label].call("Messages sent:")} #{msg_count}"

      # Agents used
      if all_agents.any?
        agents_list = all_agents.map { |agent| @colors[:agent_label].call(agent.to_s) }.join(", ")
        puts "  #{@colors[:agent_label].call("Agents used:")} #{agents_list}"
      end

      # LLM requests
      puts "  #{@colors[:system].call("LLM Requests:")} #{total_llm_requests}"

      # Tool calls
      puts "  #{@colors[:system].call("Tool Calls:")} #{total_tool_calls}"

      # Tokens
      formatted_tokens = SwarmCLI::UI::Formatters::Number.format(total_tokens)
      puts "  #{@colors[:system].call("Total Tokens:")} #{formatted_tokens}"

      # Cost (colored)
      formatted_cost = SwarmCLI::UI::Formatters::Cost.format(total_cost, pastel: @pastel)
      puts "  #{@colors[:system].call("Total Cost:")} #{formatted_cost}"

      # Duration
      formatted_duration = SwarmCLI::UI::Formatters::Time.duration(session_duration)
      puts "  #{@colors[:system].call("Session Duration:")} #{formatted_duration}"

      puts ""
      puts divider
      puts ""
    end

    def render_error(message)
      icon = @colors[:error_icon].call("✗")
      text = @colors[:error].call(message)
      "#{icon} #{text}"
    end

    def render_system_message(text)
      bracket_open = @colors[:system_bracket].call("[")
      bracket_close = @colors[:system_bracket].call("]")
      content = @colors[:system].call(text)
      "#{bracket_open}#{content}#{bracket_close}"
    end

    def configure_completion_ui
      # Only configure if Reline::Face is available (Ruby 3.1+)
      return unless defined?(Reline::Face)

      Reline::Face.config(:completion_dialog) do |conf|
        conf.define(:default, foreground: :white, background: :blue)
        conf.define(:enhanced, foreground: :black, background: :cyan) # Selected item
        conf.define(:scrollbar, foreground: :cyan, background: :blue)
      end
    rescue StandardError
      # Ignore errors if Face configuration fails
    end

    def setup_fuzzy_completion
      # Capture COMMANDS for use in lambda
      commands = COMMANDS

      # Capture file completion logic for use in lambda (since lambda runs in different context)
      file_completions = lambda do |target|
        has_at_prefix = target.start_with?("@")
        query = has_at_prefix ? target[1..] : target

        next Dir.glob("*").sort.first(20) if query.empty?

        # Find files matching query anywhere in path
        pattern = "**/*#{query}*"
        found = Dir.glob(pattern, File::FNM_CASEFOLD).reject do |path|
          path.split("/").any? { |part| part.start_with?(".") }
        end.sort.first(20)

        # Add @ prefix if needed
        has_at_prefix ? found.map { |p| "@#{p}" } : found
      end

      # Custom dialog proc for fuzzy file/command completion
      fuzzy_proc = lambda do
        # State: [pre, target, post, matches, pointer, navigating]

        # Check if this is a navigation key press
        is_nav_key = key&.match?(dialog.name)

        # If we were in navigation mode and user typed a regular key (not Tab), exit nav mode
        if !context.empty? && context.size >= 6 && context[5] && !is_nav_key
          context[5] = false # Exit navigation mode
        end

        # Early check: if user typed and current target has spaces, close dialog
        unless is_nav_key || context.empty?
          _, target_check, = retrieve_completion_block
          if target_check.include?(" ")
            context.clear
            return
          end
        end

        # Detect if we should recalculate matches
        should_recalculate = if context.empty?
          true # First time - initialize
        elsif is_nav_key
          false # Navigation key - don't recalculate, just cycle
        elsif context.size >= 6 && context[5]
          false # We're in navigation mode - keep matches stable
        else
          true # User typed something - recalculate
        end

        # Recalculate matches if user typed
        if should_recalculate
          preposing, target, postposing = retrieve_completion_block

          # Don't show completions if the target itself has spaces
          # (allows "@lib/swarm" in middle of sentence like "check @lib/swarm file")
          return if target.include?(" ")

          matches = if target.start_with?("/")
            # Command completions
            query = target[1..] || ""
            commands.keys.map(&:to_s).select do |cmd|
              query.empty? || cmd.downcase.include?(query.downcase)
            end.sort
          elsif target.start_with?("@") || target.include?("/")
            # File path completions - use captured lambda
            file_completions.call(target)
          end

          return if matches.nil? || matches.empty?

          # Store fresh values - not in navigation mode yet
          context.clear
          context.push(preposing, target, postposing, matches, 0, false)
        end

        # Use stored values
        stored_pre, _, stored_post, matches, pointer, _ = context

        # Handle navigation keys
        if is_nav_key
          # Check if Enter was pressed - close dialog without submitting
          # Must check key.char (not method_symbol, which is :fuzzy_complete when trapped)
          if key.char == "\r" || key.char == "\n"
            # Enter pressed - accept completion and close dialog
            # Clear context so dialog doesn't reappear
            context.clear
            return
          end

          # Update pointer (cycle through matches)
          # Tab is now bound to :fuzzy_complete, Shift-Tab to :completion_journey_up
          pointer = if key.method_symbol == :completion_journey_up
            # Shift-Tab - cycle backward
            (pointer - 1) % matches.size
          else
            # Tab (:fuzzy_complete) - cycle forward
            (pointer + 1) % matches.size
          end

          # Update line buffer with selected completion
          selected = matches[pointer]

          # Get current line editor state
          le = @line_editor

          new_line = stored_pre + selected + stored_post
          new_cursor = stored_pre.length + selected.bytesize

          # Update buffer using public APIs
          le.set_current_line(new_line)
          le.byte_pointer = new_cursor

          # Update state - mark as navigating so we don't recalculate
          context[4] = pointer
          context[5] = true # Now in navigation mode
        end

        # Set visual highlight
        dialog.pointer = pointer

        # Trap Shift-Tab and Enter (Tab is already bound to our dialog)
        dialog.trap_key = [[27, 91, 90], [13]]

        # Position dropdown
        x = [cursor_pos.x, 0].max
        y = 0

        # Return dialog
        Reline::DialogRenderInfo.new(
          pos: Reline::CursorPos.new(x, y),
          contents: matches,
          scrollbar: true,
          height: [15, matches.size].min,
          face: :completion_dialog,
        )
      end

      # Register the custom fuzzy dialog
      Reline.add_dialog_proc(:fuzzy_complete, fuzzy_proc, [])
    end
  end
end
