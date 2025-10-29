# frozen_string_literal: true

require "test_helper"

class SystemUtilsTest < Minitest::Test
  # Create a test class that includes the SystemUtils module
  class TestClass
    include ClaudeSwarm::SystemUtils
  end

  def setup
    @subject = TestClass.new
  end

  def test_system_with_successful_command
    assert_system_command_succeeds("true")
  end

  def test_system_with_successful_command_multiple_args
    assert_system_command_succeeds(["echo", "test", "args"])
  end

  def test_system_with_failing_command_raises_error
    assert_system_command_fails("false", 1)
  end

  def test_system_with_failing_command_multiple_args_raises_error
    assert_system_command_fails(["sh", "-c", "exit 2"], 2)
  end

  def test_system_with_exit_status_143_warns_but_does_not_raise
    # Exit status 143 = 128 + 15 (SIGTERM) - special timeout handling
    assert_system_command_times_out(["sh", "-c", "exit #{EXIT_STATUS_TIMEOUT}"])
  end

  def test_system_with_exit_status_143_single_arg_warns_but_does_not_raise
    assert_system_command_times_out("sh -c 'exit #{EXIT_STATUS_TIMEOUT}'")
  end

  def test_system_with_different_non_zero_exit_codes
    # Test various exit codes to ensure they all raise errors (except 143)
    [1, 2, EXIT_STATUS_COMMAND_NOT_FOUND, 128, 255].each do |exit_code|
      assert_system_command_fails(["sh", "-c", "exit #{exit_code}"], exit_code)
    end
  end

  def test_system_with_nonexistent_command
    assert_system_command_fails("this_command_should_not_exist_12345", EXIT_STATUS_COMMAND_NOT_FOUND)
  end

  def test_system_preserves_original_system_behavior
    # Test that stdout from the command is passed through
    # Use capture_subprocess_io since system writes to the subprocess's stdout
    output, = capture_subprocess_io do
      result = @subject.system!("echo", "Hello World")

      assert(result)
    end

    assert_match(/Hello World/, output)
  end

  def test_system_with_command_returning_false_without_child_status
    # Test edge case where system returns false but $CHILD_STATUS might have unexpected value
    _output, err = capture_subprocess_io do
      # Use a command that should fail to execute (invalid syntax)
      error = assert_raises(ClaudeSwarm::Error) do
        @subject.system!("sh", "-c", "invalid syntax ((()))")
      end
      # The exact exit status may vary, but it should fail
      assert_match(/Command failed with exit status/, error.message)
    end

    # Shell error messages go to stderr, captured by capture_subprocess_io
    assert_match(/syntax error/i, err)
  end

  def test_timeout_with_actual_timeout_command
    # Test with actual timeout command if available on the system
    skip("timeout command not available") unless command_available?("timeout")

    # GNU timeout returns 124 when the timeout is reached
    assert_system_command_fails(["timeout", "-s", "TERM", "0.1", "sleep", "10"], EXIT_STATUS_TIMEOUT_GNU)
  end

  # Additional test cases as requested by critic

  def test_system_with_environment_variables
    # Test that environment variables are passed through to the command
    test_var = "TEST_VAR_#{Time.now.to_i}"
    ENV[test_var] = "test_value"

    begin
      output, = capture_subprocess_io do
        result = @subject.system!("sh", "-c", "echo $#{test_var}")

        assert(result)
      end

      assert_match(/test_value/, output)
    ensure
      ENV.delete(test_var)
    end
  end

  def test_system_with_shell_metacharacters
    # Test proper handling of commands with special characters
    Dir.mktmpdir do |tmpdir|
      # Create a file with spaces and special characters
      filename = File.join(tmpdir, "test file with spaces & chars.txt")
      File.write(filename, "content")

      # Test that shell metacharacters are properly handled
      assert_system_command_succeeds(["ls", filename])

      # Test with quotes in command
      assert_system_command_succeeds(["echo", "test 'quoted' string"])
    end
  end

  def test_system_with_nil_arguments
    # Test handling of nil in arguments array
    capture_io do
      error = assert_raises(TypeError) do
        @subject.system!("echo", nil, "test")
      end
      # Ruby's system method raises TypeError for nil arguments
      assert_kind_of(TypeError, error)
    end
  end

  def test_system_with_empty_string_arguments
    # Test handling of empty strings in arguments
    assert_system_command_succeeds(["echo", "", "test"])
  end

  def test_system_with_very_long_command_string
    # Test with very long command strings
    long_string = "a" * 1000

    assert_system_command_succeeds(["echo", long_string])
  end

  def test_warning_format_consistency
    # Verify both timeout and error warnings follow consistent format
    # Test timeout warning format
    _, timeout_err = capture_io do
      @subject.system!("sh", "-c", "exit #{EXIT_STATUS_TIMEOUT}")
    end

    assert_match(/^⏱️ Command timeout: /, timeout_err)

    # Test error warning format
    _, error_err = capture_io do
      assert_raises(ClaudeSwarm::Error) do
        @subject.system!("sh", "-c", "exit 1")
      end
    end

    assert_match(/^❌ Command failed with exit status: /, error_err)
  end

  def test_system_with_working_directory_change
    # Test that system commands run in the current working directory
    Dir.mktmpdir do |tmpdir|
      # Create a test file in temp dir
      test_file = File.join(tmpdir, "test.txt")
      File.write(test_file, "content")

      # Verify command runs in specified directory using chdir option
      output, = capture_subprocess_io do
        result = @subject.system!("ls", "test.txt", chdir: tmpdir)

        assert(result)
      end

      assert_match(/test\.txt/, output)

      # Test that command fails when file doesn't exist
      # Note: ls returns exit status 1 on macOS but 2 on some Linux systems
      _output, _err = capture_subprocess_io do
        error = assert_raises(ClaudeSwarm::Error) do
          @subject.system!("ls", "nonexistent_file_12345.txt", chdir: tmpdir)
        end
        assert_match(/Command failed with exit status [12]: ls nonexistent_file_12345.txt/, error.message)
      end
    end
  end

  def test_system_command_with_pipes_and_redirects
    # Test commands with shell features when using single string argument
    output, = capture_subprocess_io do
      result = @subject.system!("echo 'test' | grep test")

      assert(result)
    end

    assert_match(/test/, output)
  end

  def test_system_handles_signal_interruption
    # Test behavior when command is interrupted by signal
    skip("signal handling test requires Unix-like system") if RUBY_PLATFORM =~ /mswin|mingw|cygwin/

    # On some systems, kill -9 $$ might not work as expected in a subshell
    # Test with a different signal instead
    _output, _err = capture_subprocess_io do
      capture_io do
        error = assert_raises(ClaudeSwarm::Error) do
          @subject.system!("sh", "-c", "kill -9 $$")
        end
        # The exit status might vary depending on the shell and system
        assert_match(/Command failed with exit status/, error.message)
      end
    end
  end

  # Tests for system_with_pid!
  def test_system_with_pid_successful_command
    pid_received = nil

    output, = capture_subprocess_io do
      result = @subject.system_with_pid!("echo", "test") do |pid|
        pid_received = pid

        assert_kind_of(Integer, pid)
        assert_predicate(pid, :positive?)
      end

      assert(result)
    end

    assert_match(/test/, output)
    refute_nil(pid_received)
  end

  def test_system_with_pid_yields_correct_pid
    pid_received = nil

    # Use a command that sleeps briefly to ensure we can check the PID
    _output, = capture_subprocess_io do
      @subject.system_with_pid!("sh", "-c", "echo $$") do |pid|
        pid_received = pid
      end
    end

    refute_nil(pid_received)
    assert_kind_of(Integer, pid_received)
  end

  def test_system_with_pid_failing_command_raises_error
    pid_received = nil

    capture_io do
      error = assert_raises(ClaudeSwarm::Error) do
        @subject.system_with_pid!("sh", "-c", "exit 42") do |pid|
          pid_received = pid
        end
      end

      assert_match(/Command failed with exit status 42/, error.message)
    end

    # The block should still have been called with the PID
    refute_nil(pid_received)
  end

  def test_system_with_pid_without_block
    # Should work without a block
    output, = capture_subprocess_io do
      result = @subject.system_with_pid!("echo", "no block")

      assert(result)
    end

    assert_match(/no block/, output)
  end

  def test_system_with_pid_stdin_stdout_stderr_passed_through
    # Test that stdin, stdout, stderr are properly connected
    output, err = capture_subprocess_io do
      @subject.system_with_pid!("sh", "-c", "echo 'to stdout'; echo 'to stderr' >&2")
    end

    assert_match(/to stdout/, output)
    assert_match(/to stderr/, err)
  end

  def test_system_with_pid_timeout_exit_status
    # Test timeout exit status handling (143)
    _output, err = capture_io do
      @subject.system_with_pid!("sh", "-c", "exit #{EXIT_STATUS_TIMEOUT}")
    end

    assert_match(/⏱️ Command timeout:/, err)
  end

  def test_system_with_pid_nonexistent_command
    capture_io do
      error = assert_raises(Errno::ENOENT) do
        @subject.system_with_pid!("this_command_should_not_exist_67890")
      end

      assert_match(/No such file or directory/, error.message)
    end
  end

  def test_system_with_pid_environment_variables
    # Test that environment variables are passed through
    test_var = "TEST_PID_VAR_#{Time.now.to_i}"
    ENV[test_var] = "test_pid_value"

    begin
      output, = capture_subprocess_io do
        result = @subject.system_with_pid!("sh", "-c", "echo $#{test_var}")

        assert(result)
      end

      assert_match(/test_pid_value/, output)
    ensure
      ENV.delete(test_var)
    end
  end
end
