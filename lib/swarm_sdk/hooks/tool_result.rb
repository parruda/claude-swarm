# frozen_string_literal: true

module SwarmSDK
  module Hooks
    # Represents the result of a tool execution
    #
    # This is a simple value object that wraps tool execution results
    # in a consistent format for post-tool-use hooks.
    #
    # @example Access tool result in a hook
    #   swarm.add_callback(:post_tool_use) do |context|
    #     if context.tool_result.success?
    #       puts "Tool succeeded: #{context.tool_result.content}"
    #     else
    #       puts "Tool failed: #{context.tool_result.error}"
    #     end
    #   end
    class ToolResult
      attr_reader :tool_call_id, :tool_name, :content, :success, :error

      # @param tool_call_id [String] ID of the tool call this result corresponds to
      # @param tool_name [String] Name of the tool that was executed
      # @param content [String, nil] Result content (if successful)
      # @param success [Boolean] Whether the tool execution succeeded
      # @param error [String, nil] Error message (if failed)
      def initialize(tool_call_id:, tool_name:, content: nil, success: true, error: nil)
        @tool_call_id = tool_call_id
        @tool_name = tool_name
        @content = content
        @success = success
        @error = error
      end

      # Check if the tool execution succeeded
      #
      # @return [Boolean] true if successful
      def success?
        @success
      end

      # Check if the tool execution failed
      #
      # @return [Boolean] true if failed
      def failure?
        !@success
      end

      # Convert to hash representation
      #
      # @return [Hash] Hash with all result attributes
      def to_h
        {
          tool_call_id: @tool_call_id,
          tool_name: @tool_name,
          content: @content,
          success: @success,
          error: @error,
        }
      end
    end
  end
end
