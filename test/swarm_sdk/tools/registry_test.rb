# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Tools
    class RegistryTest < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
      end

      def teardown
        FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
      end

      def test_registry_get_tool_special
        # File tools that require agent context return :special
        result = Registry.get(:Read)

        assert_equal(:special, result)
      end

      def test_registry_get_tool_regular
        # Regular tools return their class
        tool_class = Registry.get(:Bash)

        assert_equal(Bash, tool_class)
      end

      def test_registry_get_tool_string_name
        result = Registry.get("Read")

        assert_equal(:special, result)
      end

      def test_registry_get_many
        results = Registry.get_many([:Read, :Write, :Edit])

        assert_equal(3, results.size)
        # File tools return :special
        assert_equal(:special, results[0])
        assert_equal(:special, results[1])
        assert_equal(:special, results[2])
      end

      def test_registry_get_many_with_regular_tools
        results = Registry.get_many([:Bash, :Grep, :Glob])

        assert_equal(3, results.size)
        assert_equal(Bash, results[0])
        assert_equal(Grep, results[1])
        assert_equal(Glob, results[2])
      end

      def test_registry_get_many_invalid_tool
        error = assert_raises(ConfigurationError) do
          Registry.get_many([:Read, :InvalidTool])
        end
        assert_includes(error.message, "Unknown tool: InvalidTool")
      end

      def test_registry_exists
        assert(Registry.exists?(:Read))
        assert(Registry.exists?("Read"))
        assert(Registry.exists?(:Bash))
        refute(Registry.exists?(:InvalidTool))
      end

      def test_registry_available_names
        names = Registry.available_names

        assert_includes(names, :Read)
        assert_includes(names, :Write)
        assert_includes(names, :Edit)
        assert_includes(names, :MultiEdit)
        assert_includes(names, :TodoWrite)
        assert_includes(names, :Bash)
        assert_includes(names, :Grep)
        assert_includes(names, :Glob)
        assert_includes(names, :WebFetch)
        # Scratchpad tools (simplified)
        assert_includes(names, :ScratchpadWrite)
        assert_includes(names, :ScratchpadRead)
        assert_includes(names, :ScratchpadList)
        # Memory tools
        assert_includes(names, :MemoryWrite)
        assert_includes(names, :MemoryRead)
        assert_includes(names, :MemoryDelete)
      end

      def test_registry_validate
        invalid = Registry.validate([:Read, :InvalidTool, :Write])

        assert_equal([:InvalidTool], invalid)
      end

      def test_special_tools_can_be_instantiated
        # File tools should be instantiable with agent_name parameter
        assert_respond_to(Read, :new)
        assert_respond_to(Write, :new)
        assert_respond_to(Edit, :new)
        assert_respond_to(MultiEdit, :new)
        assert_respond_to(TodoWrite, :new)
      end

      def test_special_tools_create_instances
        # Should be able to create tool instances for agents
        read_tool = Read.new(agent_name: :test, directory: @temp_dir)

        assert_respond_to(read_tool, :execute)

        write_tool = Write.new(agent_name: :test, directory: @temp_dir)

        assert_respond_to(write_tool, :execute)

        edit_tool = Edit.new(agent_name: :test, directory: @temp_dir)

        assert_respond_to(edit_tool, :execute)
      end
    end
  end
end
