# frozen_string_literal: true

require "fast-mcp-annotations"
require_relative "executor"
require_relative "session_manager"

module ClaudeSwarmMultiModel
  module MCP
    class Server
      def initialize(config = {})
        @config = config
        @session_manager = SessionManager.new
        @executor = Executor.new(config)
        @server = setup_server
      end

      def run
        @server.run
      end

      private

      def setup_server
        session_manager = @session_manager
        executor = @executor
        config = @config

        FastMcp::Server.new(
          name: "claude-swarm-multi-model",
          version: ClaudeSwarmMultiModel::VERSION
        ) do
          # Task tool for executing prompts
          tool :task do
            description "Execute a task using the configured LLM provider"

            arguments do
              required(:prompt).filled(:string).description("The task or question to execute")
              optional(:model).filled(:string).description("Override the default model")
              optional(:temperature).filled(:float).description("Override the default temperature")
              optional(:max_tokens).filled(:integer).description("Override the default max tokens")
              optional(:stream).filled(:bool).description("Whether to stream the response")
              optional(:system_prompt).filled(:string).description("System prompt to use")
            end

            handler do |args|
              session_manager.start_session unless session_manager.active?

              options = {
                model: args[:model] || config[:model],
                temperature: args[:temperature] || config[:temperature],
                max_tokens: args[:max_tokens] || config[:max_tokens],
                stream: args[:stream] || false,
                system_prompt: args[:system_prompt] || config[:system_prompt]
              }

              begin
                result = executor.execute(args[:prompt], options)

                # Track usage
                session_manager.add_message(
                  role: "user",
                  content: args[:prompt]
                )
                session_manager.add_message(
                  role: "assistant",
                  content: result[:content],
                  usage: result[:usage]
                )

                {
                  content: result[:content],
                  model: result[:model],
                  usage: result[:usage]
                }
              rescue StandardError => e
                {
                  error: e.message,
                  type: e.class.name
                }
              end
            end
          end

          # Session info tool
          tool :session_info do
            description "Get information about the current LLM session"

            handler do |_args|
              {
                active: session_manager.active?,
                session_id: session_manager.session_id,
                message_count: session_manager.message_count,
                total_tokens: session_manager.total_tokens,
                model: config[:model],
                provider: config[:provider]
              }
            end
          end

          # Reset session tool
          tool :reset_session do
            description "Reset the current LLM session"

            handler do |_args|
              session_manager.reset!
              {
                message: "Session reset successfully",
                session_id: session_manager.session_id
              }
            end
          end
        end
      end
    end
  end
end
