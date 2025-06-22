# frozen_string_literal: true

require "test_helper"

class BaseExecutorTest < Minitest::Test
  def setup
    @session_path = Dir.mktmpdir
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path
  end

  def teardown
    FileUtils.rm_rf(@session_path)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def test_initialize_with_required_parameters
    executor = ClaudeSwarm::BaseExecutor.new(
      working_directory: "/tmp/test",
      instance_name: "test_instance",
      instance_id: "test_123",
      calling_instance: "caller",
      calling_instance_id: "caller_123"
    )

    assert_equal "/tmp/test", executor.working_directory
    assert_nil executor.session_id
    assert_nil executor.last_response
    assert_instance_of Logger, executor.logger
    assert_equal @session_path, executor.session_path
  end

  def test_initialize_with_session_id
    executor = ClaudeSwarm::BaseExecutor.new(
      working_directory: "/tmp/test",
      session_id: "existing_session"
    )

    assert_equal "existing_session", executor.session_id
  end

  def test_execute_raises_not_implemented_error
    executor = ClaudeSwarm::BaseExecutor.new

    assert_raises(NotImplementedError) do
      executor.execute("test prompt")
    end
  end

  def test_reset_session
    executor = ClaudeSwarm::BaseExecutor.new(session_id: "test_session")
    executor.reset_session

    assert_nil executor.session_id
    assert_nil executor.last_response
  end

  def test_has_session
    executor = ClaudeSwarm::BaseExecutor.new

    refute_predicate executor, :has_session?

    executor = ClaudeSwarm::BaseExecutor.new(session_id: "test_session")

    assert_predicate executor, :has_session?
  end

  def test_logging_setup
    ClaudeSwarm::BaseExecutor.new(
      instance_name: "test_instance",
      instance_id: "test_123"
    )

    log_file = File.join(@session_path, "session.log")

    assert_path_exists log_file

    log_content = File.read(log_file)

    assert_match(/Started BaseExecutor for instance: test_instance \(test_123\)/, log_content)
  end

  def test_append_to_session_json
    ClaudeSwarm::BaseExecutor.new(
      instance_name: "test_instance",
      instance_id: "test_123",
      calling_instance: "caller",
      calling_instance_id: "caller_123"
    )

    # This method is private, so we'll test it indirectly through the logging
    json_file = File.join(@session_path, "session.log.json")

    # The file should not exist yet
    refute_path_exists json_file
  end

  def test_error_classes_are_defined
    assert ClaudeSwarm::BaseExecutor::ExecutionError
    assert ClaudeSwarm::BaseExecutor::ParseError
  end
end
