# frozen_string_literal: true

require "test_helper"
require "tempfile"

module SwarmSDK
  class HooksExecutorTest < Minitest::Test
    def test_execute_with_exit_0_returns_continue
      # Create a script that exits 0 (success)
      with_script("exit 0") do |script_path|
        result = SwarmSDK::Hooks::ShellExecutor.execute(
          command: script_path,
          input_json: { event: "test" },
          agent_name: :test_agent,
          swarm_name: "Test Swarm",
        )

        assert_instance_of(Hooks::Result, result)
        assert_predicate(result, :continue?)
        refute_predicate(result, :halt?)
      end
    end

    def test_execute_with_exit_2_returns_halt
      # Create a script that exits 2 (block with error)
      # Error message goes to stderr (implementation reads from stderr, not stdout)
      script = <<~SCRIPT
        echo "Validation failed: syntax error" >&2
        exit 2
      SCRIPT

      with_script(script) do |script_path|
        result = nil
        capture_io do
          result = SwarmSDK::Hooks::ShellExecutor.execute(
            command: script_path,
            input_json: { tool: "Write", parameters: {} },
            event: :pre_tool_use,
            agent_name: :test_agent,
            swarm_name: "Test Swarm",
          )
        end

        assert_instance_of(Hooks::Result, result)
        assert_predicate(result, :halt?)
        assert_includes(result.value, "Validation failed")
      end
    end

    def test_execute_with_other_exit_code_returns_continue
      # Create a script that exits 1 (non-blocking error)
      with_script("exit 1") do |script_path|
        result = nil
        capture_io do
          result = SwarmSDK::Hooks::ShellExecutor.execute(
            command: script_path,
            input_json: { event: "test" },
            agent_name: :test_agent,
            swarm_name: "Test Swarm",
          )
        end

        # Should continue despite error
        assert_instance_of(Hooks::Result, result)
        assert_predicate(result, :continue?)
        refute_predicate(result, :halt?)
      end
    end

    def test_execute_with_timeout_returns_continue
      # Create a script that sleeps longer than timeout
      with_script("sleep 10") do |script_path|
        result = nil
        capture_io do
          result = SwarmSDK::Hooks::ShellExecutor.execute(
            command: script_path,
            input_json: { event: "test" },
            timeout: 1, # 1 second timeout
            agent_name: :test_agent,
            swarm_name: "Test Swarm",
          )
        end

        # Should continue despite timeout
        assert_instance_of(Hooks::Result, result)
        assert_predicate(result, :continue?)
      end
    end

    def test_execute_provides_json_on_stdin
      # Script that reads JSON from stdin and validates it
      # Exits 0 if JSON contains expected fields, exits 1 otherwise
      script = <<~SCRIPT
        input=$(cat)
        if echo "$input" | grep -q "pre_tool_use" && echo "$input" | grep -q "Write"; then
          exit 0
        else
          exit 1
        fi
      SCRIPT

      with_script(script) do |script_path|
        input_json = {
          event: "pre_tool_use",
          tool: "Write",
          parameters: { file_path: "test.rb" },
        }

        result = nil
        capture_io do
          result = SwarmSDK::Hooks::ShellExecutor.execute(
            command: script_path,
            input_json: input_json,
            agent_name: :test_agent,
            swarm_name: "Test Swarm",
          )
        end

        # Verify script found expected JSON fields on stdin (exit 0 = success)
        assert_instance_of(Hooks::Result, result)
        assert_predicate(result, :continue?)
      end
    end

    def test_execute_sets_environment_variables
      # Script that writes environment variables to a temp file for verification
      temp_file = File.join(Dir.tmpdir, "swarm_sdk_env_test_#{Process.pid}.txt")

      script = <<~SCRIPT
        echo "PROJECT_DIR: $SWARM_SDK_PROJECT_DIR" > #{temp_file}
        echo "AGENT: $SWARM_SDK_AGENT_NAME" >> #{temp_file}
        echo "SWARM: $SWARM_SDK_SWARM_NAME" >> #{temp_file}
        exit 0
      SCRIPT

      with_script(script) do |script_path|
        capture_io do
          SwarmSDK::Hooks::ShellExecutor.execute(
            command: script_path,
            input_json: { event: "test" },
            agent_name: :backend,
            swarm_name: "Dev Team",
          )
        end

        # Read the temp file and verify env vars were set
        assert_path_exists(temp_file, "Script should have created temp file")
        content = File.read(temp_file)

        assert_includes(content, "PROJECT_DIR: #{Dir.pwd}")
        assert_includes(content, "AGENT: backend")
        assert_includes(content, "SWARM: Dev Team")
      ensure
        File.delete(temp_file) if File.exist?(temp_file)
      end
    end

    def test_execute_with_nonexistent_command_returns_continue
      result = nil
      capture_io do
        result = SwarmSDK::Hooks::ShellExecutor.execute(
          command: "/nonexistent/command",
          input_json: { event: "test" },
          agent_name: :test_agent,
          swarm_name: "Test Swarm",
        )
      end

      # Should continue despite error
      assert_instance_of(Hooks::Result, result)
      assert_predicate(result, :continue?)
    end

    private

    def with_script(content)
      Tempfile.create(["hook_test", ".sh"]) do |file|
        file.write("#!/usr/bin/env bash\n")
        file.write("set -e\n") # Exit on error
        file.write(content)
        file.flush
        file.chmod(0o755)
        # Invoke bash explicitly to ensure script runs correctly in all environments
        yield "bash #{file.path}"
      end
    end
  end
end
