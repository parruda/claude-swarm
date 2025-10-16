# frozen_string_literal: true

module SwarmSDK
  module Hooks
    # Represents a tool call in the hooks system
    #
    # This is a simple value object that wraps tool call information
    # from RubyLLM in a consistent, immutable format for hooks.
    #
    # @example Access tool call information in a hook
    #   swarm.add_callback(:pre_tool_use) do |context|
    #     puts "Tool: #{context.tool_call.name}"
    #     puts "Parameters: #{context.tool_call.parameters.inspect}"
    #   end
    class ToolCall
      attr_reader :id, :name, :parameters

      # @param id [String] Unique identifier for this tool call
      # @param name [String] Name of the tool being called
      # @param parameters [Hash] Parameters passed to the tool
      def initialize(id:, name:, parameters:)
        @id = id
        @name = name
        @parameters = parameters
      end

      # Convert to hash representation
      #
      # @return [Hash] Hash with id, name, and parameters
      def to_h
        { id: @id, name: @name, parameters: @parameters }
      end
    end
  end
end
