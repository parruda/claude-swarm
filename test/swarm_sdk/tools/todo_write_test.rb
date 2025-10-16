# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Tools
    class TodoWriteTest < Minitest::Test
      def test_todo_write_creates_agent_specific_tool
        tool = TodoWrite.new(agent_name: :test_agent)

        assert_kind_of(RubyLLM::Tool, tool)
      end

      def test_todo_write_stores_todos_per_agent
        agent1_tool = TodoWrite.new(agent_name: :agent1)
        agent2_tool = TodoWrite.new(agent_name: :agent2)

        todos1_json = '[{"content":"Task 1","status":"in_progress","activeForm":"Doing task 1"},{"content":"Task 2","status":"pending","activeForm":"Doing task 2"}]'
        todos2_json = '[{"content":"Different task","status":"in_progress","activeForm":"Doing different task"}]'

        agent1_tool.execute(todos_json: todos1_json)
        agent2_tool.execute(todos_json: todos2_json)

        stored_todos1 = Stores::TodoManager.get_todos(:agent1)
        stored_todos2 = Stores::TodoManager.get_todos(:agent2)

        assert_equal(2, stored_todos1.size)
        assert_equal(1, stored_todos2.size)
        assert_equal("Task 1", stored_todos1[0][:content])
        assert_equal("Different task", stored_todos2[0][:content])
      end

      def test_todo_write_validates_required_fields
        tool = TodoWrite.new(agent_name: :test_agent)

        # Missing status
        result = tool.execute(todos_json: '[{"content":"Test","activeForm":"Testing"}]')

        assert_includes(result, "Error")
        assert_includes(result, "missing required field 'status'")

        # Missing content
        result = tool.execute(todos_json: '[{"status":"pending","activeForm":"Testing"}]')

        assert_includes(result, "missing required field 'content'")

        # Missing activeForm
        result = tool.execute(todos_json: '[{"content":"Test","status":"pending"}]')

        assert_includes(result, "missing required field 'activeForm'")
      end

      def test_todo_write_validates_exactly_one_in_progress
        tool = TodoWrite.new(agent_name: :test_agent)

        # No in_progress tasks
        result = tool.execute(todos_json: '[{"content":"Task 1","status":"pending","activeForm":"Doing task 1"},{"content":"Task 2","status":"completed","activeForm":"Doing task 2"}]')

        assert_includes(result, "Warning")
        assert_includes(result, "No tasks marked as in_progress")

        # Multiple in_progress tasks
        result = tool.execute(todos_json: '[{"content":"Task 1","status":"in_progress","activeForm":"Doing task 1"},{"content":"Task 2","status":"in_progress","activeForm":"Doing task 2"}]')

        assert_includes(result, "Warning")
        assert_includes(result, "Multiple tasks marked as in_progress")
      end

      def test_todo_write_validates_status_values
        tool = TodoWrite.new(agent_name: :test_agent)

        result = tool.execute(todos_json: '[{"content":"Test","status":"invalid_status","activeForm":"Testing"}]')

        assert_includes(result, "Error")
        assert_includes(result, "invalid status")
      end

      def test_todo_write_success_message
        tool = TodoWrite.new(agent_name: :test_agent)

        result = tool.execute(todos_json: '[{"content":"Task 1","status":"in_progress","activeForm":"Doing task 1"}]')

        assert_includes(result, "Your todo list has changed")
        assert_includes(result, "Task 1 (in_progress)")
      end

      def test_todo_write_validates_json_format
        tool = TodoWrite.new(agent_name: :test_agent)

        # Invalid JSON
        result = tool.execute(todos_json: "not valid json")

        assert_includes(result, "Error")
        assert_includes(result, "Invalid JSON format")
      end

      def test_todo_manager_clear_todos
        Stores::TodoManager.set_todos(:agent1, [{ content: "Test" }])
        Stores::TodoManager.clear_todos(:agent1)

        assert_empty(Stores::TodoManager.get_todos(:agent1))
      end

      def test_todo_manager_summary
        Stores::TodoManager.clear_all

        Stores::TodoManager.set_todos(:agent1, [{ content: "Test 1" }, { content: "Test 2" }])
        Stores::TodoManager.set_todos(:agent2, [{ content: "Test 3" }])

        summary = Stores::TodoManager.summary

        assert_equal(2, summary[:agent1])
        assert_equal(1, summary[:agent2])
      end

      def test_todo_write_validates_non_hash_todo
        tool = TodoWrite.new(agent_name: :test_agent)

        # Todo is not a hash
        result = tool.execute(todos_json: '["not a hash"]')

        assert_includes(result, "Error")
        assert_includes(result, "must be a hash")
      end

      def test_todo_write_validates_empty_content
        tool = TodoWrite.new(agent_name: :test_agent)

        # Empty content
        result = tool.execute(todos_json: '[{"content":"","status":"pending","activeForm":"Testing"}]')

        assert_includes(result, "Error")
        assert_includes(result, "has empty content")
      end

      def test_todo_write_validates_whitespace_only_content
        tool = TodoWrite.new(agent_name: :test_agent)

        # Whitespace-only content
        result = tool.execute(todos_json: '[{"content":"   ","status":"pending","activeForm":"Testing"}]')

        assert_includes(result, "Error")
        assert_includes(result, "has empty content")
      end

      def test_todo_write_validates_empty_active_form
        tool = TodoWrite.new(agent_name: :test_agent)

        # Empty activeForm
        result = tool.execute(todos_json: '[{"content":"Task","status":"pending","activeForm":""}]')

        assert_includes(result, "Error")
        assert_includes(result, "has empty activeForm")
      end

      def test_todo_write_validates_whitespace_only_active_form
        tool = TodoWrite.new(agent_name: :test_agent)

        # Whitespace-only activeForm
        result = tool.execute(todos_json: '[{"content":"Task","status":"pending","activeForm":"   "}]')

        assert_includes(result, "Error")
        assert_includes(result, "has empty activeForm")
      end

      def test_todo_write_handles_non_array_todos
        tool = TodoWrite.new(agent_name: :test_agent)

        # todos is not an array
        result = tool.execute(todos_json: '{"content":"Task","status":"pending"}')

        assert_includes(result, "Error")
        assert_includes(result, "todos must be an array")
      end
    end
  end
end
