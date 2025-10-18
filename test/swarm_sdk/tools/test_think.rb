# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Tools
    class TestThink < Minitest::Test
      def setup
        @tool = Think.new
      end

      def test_name
        assert_equal("Think", @tool.name)
      end

      def test_description_present
        refute_nil(@tool.description)
        refute_empty(@tool.description)
      end

      def test_description_emphasizes_frequent_use
        description = @tool.description

        assert_includes(description, "IMPORTANT")
        assert_includes(description, "SHOULD use this tool frequently")
        assert_includes(description, "better outcomes")
      end

      def test_description_includes_usage_examples
        description = @tool.description

        assert_includes(description, "Before starting any complex task")
        assert_includes(description, "For arithmetic and calculations")
        assert_includes(description, "After completing sub-tasks")
        assert_includes(description, "When encountering complexity")
        assert_includes(description, "For remembering context")
        assert_includes(description, "When debugging or analyzing")
        assert_includes(description, "For creative problem-solving")
      end

      def test_has_required_thoughts_parameter
        schema = @tool.to_ruby_llm_schema
        thoughts_param = schema[:input_schema][:properties][:thoughts]

        refute_nil(thoughts_param)
        assert_equal("string", thoughts_param[:type])
        assert_includes(schema[:input_schema][:required], "thoughts")
      end

      def test_execute_with_valid_thoughts
        result = @tool.execute(thoughts: "I need to plan my approach to this problem...")

        assert_equal("Thought noted.", result)
      end

      def test_execute_with_multiline_thoughts
        thoughts = <<~THOUGHTS
          I need to:
          1. Read the configuration file
          2. Parse the YAML structure
          3. Validate the required fields
          4. Return any errors found
        THOUGHTS

        result = @tool.execute(thoughts: thoughts)

        assert_equal("Thought noted.", result)
      end

      def test_execute_with_calculations
        thoughts = "If we have 150 requests/second and each takes 20ms, that's 150 * 0.02 = 3 seconds"
        result = @tool.execute(thoughts: thoughts)

        assert_equal("Thought noted.", result)
      end

      def test_execute_with_empty_thoughts
        result = @tool.execute(thoughts: "")

        assert_includes(result, "<tool_use_error>InputValidationError")
        assert_includes(result, "thoughts are required")
      end

      def test_execute_with_nil_thoughts
        result = @tool.execute(thoughts: nil)

        assert_includes(result, "<tool_use_error>InputValidationError")
        assert_includes(result, "thoughts are required")
      end

      def test_execute_with_whitespace_only_thoughts
        # Whitespace is technically valid content - the tool accepts it
        result = @tool.execute(thoughts: "   ")

        assert_equal("Thought noted.", result)
      end

      def test_tool_schema_structure
        schema = @tool.to_ruby_llm_schema

        assert_equal("Think", schema[:name])
        assert(schema.key?(:description))
        assert(schema.key?(:input_schema))

        input_schema = schema[:input_schema]

        assert_equal("object", input_schema[:type])
        assert(input_schema.key?(:properties))
        assert(input_schema.key?(:required))
        assert_includes(input_schema[:required], "thoughts")
      end

      def test_tool_is_simple_with_no_dependencies
        # The Think tool should not require any initialization parameters
        # It should work with just .new
        tool = Think.new
        result = tool.execute(thoughts: "test thought")

        assert_equal("Thought noted.", result)
      end

      def test_description_mentions_frequency_recommendation
        description = @tool.description

        assert_includes(description, "5-10 times per task")
      end

      def test_description_mentions_ruby_specific_examples
        description = @tool.description

        assert_includes(description, "Ruby") # Should have Ruby-specific examples
      end

      def test_registry_includes_think_tool
        assert(Registry.exists?(:Think))
        assert_equal(Think, Registry.get(:Think))
      end

      def test_registry_lists_think_in_available_tools
        assert_includes(Registry.available_names, :Think)
      end
    end
  end
end
