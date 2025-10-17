# frozen_string_literal: true

module SwarmCLI
  module UI
    module Renderers
      # High-level event rendering by composing lower-level components
      # Returns formatted strings for each event type
      class EventRenderer
        def initialize(pastel:, agent_badge:, depth_tracker:)
          @pastel = pastel
          @agent_badge = agent_badge
          @depth_tracker = depth_tracker
          @usage_stats = Components::UsageStats.new(pastel: pastel)
          @content_block = Components::ContentBlock.new(pastel: pastel)
          @panel = Components::Panel.new(pastel: pastel)
        end

        # Render agent thinking event
        # [12:34:56] 💭 architect (gpt-5-mini)
        def agent_thinking(agent:, model:, timestamp:)
          indent = @depth_tracker.indent(agent)
          time = Formatters::Time.timestamp(timestamp)
          agent_name = @agent_badge.render(agent, icon: UI::Icons::THINKING)
          model_info = @pastel.dim("(#{model})")

          "#{indent}#{@pastel.dim(time)} #{agent_name} #{model_info}"
        end

        # Render agent response event
        # [12:34:56] 💬 architect responded:
        def agent_response(agent:, timestamp:)
          indent = @depth_tracker.indent(agent)
          time = Formatters::Time.timestamp(timestamp)
          agent_name = @agent_badge.render(agent, icon: UI::Icons::RESPONSE)

          "#{indent}#{@pastel.dim(time)} #{agent_name} responded:"
        end

        # Render agent completion
        # ✓ architect completed
        def agent_completed(agent:)
          indent = @depth_tracker.indent(agent)
          agent_name = @agent_badge.render(agent)

          "#{indent}#{@pastel.green("#{UI::Icons::SUCCESS} #{agent_name} completed")}"
        end

        # Render tool call event
        # [12:34:56] architect 🔧 uses tool Read
        def tool_call(agent:, tool:, timestamp:)
          indent = @depth_tracker.indent(agent)
          time = Formatters::Time.timestamp(timestamp)
          agent_name = @agent_badge.render(agent)
          tool_name = @pastel.bold.blue(tool)

          "#{indent}#{@pastel.dim(time)} #{agent_name} #{@pastel.blue("#{UI::Icons::TOOL} uses tool")} #{tool_name}"
        end

        # Render tool result received
        # [12:34:56] 📥 Tool result received by architect
        def tool_result(agent:, timestamp:, tool: nil)
          indent = @depth_tracker.indent(agent)
          time = Formatters::Time.timestamp(timestamp)

          "#{indent}#{@pastel.dim(time)} #{@pastel.green("#{UI::Icons::RESULT} Tool result")} received by #{agent}"
        end

        # Render delegation event
        # [12:34:56] architect 📨 delegates to worker
        def delegation(from:, to:, timestamp:)
          indent = @depth_tracker.indent(from)
          time = Formatters::Time.timestamp(timestamp)
          from_name = @agent_badge.render(from)
          to_name = @agent_badge.render(to)

          "#{indent}#{@pastel.dim(time)} #{from_name} #{@pastel.yellow("#{UI::Icons::DELEGATE} delegates to")} #{to_name}"
        end

        # Render delegation result
        # [12:34:56] 📥 Delegation result from worker → architect
        def delegation_result(from:, to:, timestamp:)
          indent = @depth_tracker.indent(to)
          time = Formatters::Time.timestamp(timestamp)
          from_name = @agent_badge.render(from)
          to_name = @agent_badge.render(to)

          "#{indent}#{@pastel.dim(time)} #{@pastel.green("#{UI::Icons::RESULT} Delegation result")} from #{from_name} #{@pastel.dim("→")} #{to_name}"
        end

        # Render hook execution
        # [12:34:56] 🪝 Hook executed PreToolUse architect
        def hook_executed(hook_event:, agent:, timestamp:, success:, blocked:)
          indent = @depth_tracker.indent(agent)
          time = Formatters::Time.timestamp(timestamp)
          hook_display = @pastel.cyan(hook_event)
          agent_name = @agent_badge.render(agent)

          status = if blocked
            @pastel.red("BLOCKED")
          elsif success
            @pastel.green("executed")
          else
            @pastel.yellow("warning")
          end

          color = if blocked
            :red
          else
            (success ? :green : :yellow)
          end
          icon_colored = @pastel.public_send(color, UI::Icons::HOOK)

          "#{indent}#{@pastel.dim(time)} #{icon_colored} Hook #{status} #{hook_display} #{agent_name}"
        end

        # Render usage stats line
        #   5,922 tokens │ $0.0016 │ 1.5% used, 394,078 remaining
        def usage_stats(tokens:, cost:, context_pct: nil, remaining: nil, cumulative: nil, indent: 0)
          prefix = "  " * indent
          stats = @usage_stats.render(
            tokens: tokens,
            cost: cost,
            context_pct: context_pct,
            remaining: remaining,
            cumulative: cumulative,
          )

          "#{prefix}  #{stats}"
        end

        # Render tool list
        #   Tools available: Read, Write, Bash
        def tools_available(tools, indent: 0)
          return "" if tools.nil? || tools.empty?

          prefix = "  " * indent
          tools_list = tools.join(", ")

          "#{prefix}  #{@pastel.dim("Tools available: #{tools_list}")}"
        end

        # Render delegation list
        #   Can delegate to: frontend_dev, backend_dev
        def delegates_to(agents, indent: 0, color_cache:)
          return "" if agents.nil? || agents.empty?

          prefix = "  " * indent
          agent_badge = Components::AgentBadge.new(pastel: @pastel, color_cache: color_cache)
          delegates_list = agent_badge.render_list(agents)

          "#{prefix}  #{@pastel.dim("Can delegate to:")} #{delegates_list}"
        end

        # Render thinking text (italic, indented)
        def thinking_text(content, indent: 0)
          return "" if content.nil? || content.empty?

          # Strip system reminders
          text = Formatters::Text.strip_system_reminders(content)
          return "" if text.empty?

          prefix = "  " * indent

          text.split("\n").map do |line|
            "#{prefix}  #{@pastel.italic(line)}"
          end.join("\n")
        end

        # Render tool arguments
        def tool_arguments(args, indent: 0, truncate: false)
          @content_block.render_hash(args, indent: indent, label: "Arguments", truncate: truncate)
        end

        # Render tool result content
        def tool_result_content(content, indent: 0, truncate: false)
          @content_block.render_text(
            content,
            indent: indent,
            color: :bright_green,
            truncate: truncate,
            max_lines: 2,
            max_chars: 300,
          )
        end
      end
    end
  end
end
