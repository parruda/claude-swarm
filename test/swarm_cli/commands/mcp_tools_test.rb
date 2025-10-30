# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

module SwarmCLI
  module Commands
    class McpToolsTest < Minitest::Test
      def setup
        @options = McpToolsOptions.new
        @options.parse([])
      end

      # CRITICAL TEST: This would have caught the bug!
      # Bug was: SwarmSDK::Scratchpad.new(persist_to: path) - class doesn't exist
      # Fix: SwarmSDK::Tools::Stores::ScratchpadStorage.new - correct class
      #
      # This test ensures McpTools can be initialized without errors.
      # The bug would cause: "uninitialized constant SwarmSDK::Scratchpad (NameError)"
      def test_initialize_without_error
        # Should not raise NameError for missing class
        assert_silent do
          McpTools.new(@options)
        end
      end

      def test_initialize_with_no_tools
        # Default behavior: expose all available tools
        mcp_tools = McpTools.new(@options)

        assert_instance_of(McpTools, mcp_tools)
        assert_equal(@options, mcp_tools.options)
      end

      def test_initialize_with_specific_tools
        @options.parse(["Read", "Write", "Bash"])

        mcp_tools = McpTools.new(@options)

        assert_instance_of(McpTools, mcp_tools)
        assert_equal(@options, mcp_tools.options)
      end

      # Test that options are properly stored
      def test_options_accessor
        mcp_tools = McpTools.new(@options)

        assert_equal(@options, mcp_tools.options)
      end
    end
  end
end
