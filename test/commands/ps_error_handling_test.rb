# frozen_string_literal: true

require "test_helper"

class PsErrorHandlingTest < Minitest::Test
  def setup
    # Create the run directory in the test home directory (already set by test_helper)
    @run_dir = ClaudeSwarm.joined_run_dir

    # Safety check: ensure we're operating in a test directory
    validate_test_directory!(@run_dir)

    FileUtils.mkdir_p(@run_dir)
    @ps = ClaudeSwarm::Commands::Ps.new
  end

  def teardown
    # Clean up the run directory and sessions directory
    FileUtils.rm_rf(@run_dir) if @run_dir && Dir.exist?(@run_dir)
    sessions_dir = ClaudeSwarm.joined_sessions_dir
    FileUtils.rm_rf(sessions_dir) if Dir.exist?(sessions_dir)
  end

  def test_handles_corrupted_yaml_and_continues_processing
    # Create multiple session directories with symlinks
    good_session_dir = create_session("good_session", valid_config: true)
    bad_yaml_session_dir = create_session("bad_yaml_session", valid_config: false, yaml_error: true)
    another_good_session_dir = create_session("another_good_session", valid_config: true)

    # Create symlinks in run directory
    File.symlink(good_session_dir, File.join(@run_dir, "good_session"))
    File.symlink(bad_yaml_session_dir, File.join(@run_dir, "bad_yaml_session"))
    File.symlink(another_good_session_dir, File.join(@run_dir, "another_good_session"))

    # Capture output
    output, = capture_io do
      @ps.execute
    end

    # Verify that the corrupted session was NOT processed
    # The error should be caught and the session skipped
    refute_match(/bad_yaml_session/, output, "Bad session should not appear in output")

    # Verify good sessions are still processed
    assert_match(/good_session/, output)
    assert_match(/another_good_session/, output)
    assert_match(/Test Swarm/, output)
  end

  def test_handles_non_symlinks_gracefully
    # Create a regular file (not a symlink) in run directory
    regular_file = File.join(@run_dir, "not_a_symlink")
    File.write(regular_file, "some content")

    # Create a valid session with symlink
    good_session_dir = create_session("good_session", valid_config: true)
    File.symlink(good_session_dir, File.join(@run_dir, "good_session"))

    # Should not raise error and should process the good session
    output, = capture_io do
      @ps.execute
    end

    # Should not show error for non-symlink in output
    refute_match(/not_a_symlink/, output)

    # Should process the good session
    assert_match(/good_session/, output)
    assert_match(/Test Swarm/, output)
  end

  def test_handles_stale_symlinks
    # Create a symlink pointing to non-existent directory
    stale_target = ClaudeSwarm.joined_sessions_dir("non_existent_project", "non_existent_session")
    File.symlink(stale_target, File.join(@run_dir, "stale_symlink"))

    # Create a valid session
    good_session_dir = create_session("good_session", valid_config: true)
    File.symlink(good_session_dir, File.join(@run_dir, "good_session"))

    # Should handle stale symlink gracefully
    output, = capture_io do
      @ps.execute
    end

    # Should process the good session
    assert_match(/good_session/, output)
    assert_match(/Test Swarm/, output)
  end

  def test_handles_missing_config_file
    # Create session directory without config.yml
    session_dir = ClaudeSwarm.joined_sessions_dir("project", "no_config_session")
    FileUtils.mkdir_p(session_dir)

    # Create session.log.json for cost calculation
    log_file = File.join(session_dir, "session.log.json")
    File.write(log_file, "[]")

    # Create symlink
    File.symlink(session_dir, File.join(@run_dir, "no_config_session"))

    # Create a good session
    good_session_dir = create_session("good_session", valid_config: true)
    File.symlink(good_session_dir, File.join(@run_dir, "good_session"))

    # Should skip session without config
    output, = capture_io do
      @ps.execute
    end

    # Should not show the session without config
    refute_match(/no_config_session/, output)

    # Should process the good session
    assert_match(/good_session/, output)
    assert_match(/Test Swarm/, output)
  end

  def test_handles_parse_session_info_errors
    # Create a session that will cause an error in parse_session_info
    # For example, a session with invalid alias in YAML
    bad_alias_session_dir = create_session("bad_alias_session", valid_config: false, bad_alias: true)
    File.symlink(bad_alias_session_dir, File.join(@run_dir, "bad_alias_session"))

    # Create a good session
    good_session_dir = create_session("good_session", valid_config: true)
    File.symlink(good_session_dir, File.join(@run_dir, "good_session"))

    output, = capture_io do
      @ps.execute
    end

    # Bad alias session should not appear in output
    refute_match(/bad_alias_session/, output, "Bad alias session should not appear in output")

    # Should still process good session
    assert_match(/good_session/, output)
    assert_match(/Test Swarm/, output)
  end

  def test_shows_no_active_sessions_when_all_fail
    # Clean the entire run directory to ensure no leftover sessions from other tests
    Dir.glob("#{@run_dir}/*").each do |entry|
      FileUtils.rm_f(entry)
    end

    # Create only problematic sessions
    bad_yaml_session = create_session("bad_yaml", valid_config: false, yaml_error: true)
    File.symlink(bad_yaml_session, File.join(@run_dir, "bad_yaml"))

    # Add a non-symlink
    File.write(File.join(@run_dir, "regular_file"), "content")

    # Add a stale symlink
    File.symlink("/non/existent/path", File.join(@run_dir, "stale"))

    output, = capture_io do
      @ps.execute
    end

    # Should show "No active sessions"
    assert_match(/No active sessions/, output)

    # Bad session should not appear in output
    refute_match(/bad_yaml/, output)
  end

  def test_handles_standard_error_with_session_dir
    # Create a session that will cause a StandardError after session_dir is set
    # Mock a scenario where SessionCostCalculator raises an error
    session_dir = create_session("error_session", valid_config: true)
    File.symlink(session_dir, File.join(@run_dir, "error_session"))

    # Stub SessionCostCalculator to raise an error
    ClaudeSwarm::SessionCostCalculator.stub(:calculate_total_cost, ->(_) { raise StandardError, "Calculation failed" }) do
      output, = capture_io do
        @ps.execute
      end

      # Error session should not appear in output
      refute_match(/error_session/, output)

      # Should show "No active sessions" since the only session failed
      assert_match(/No active sessions/, output)
    end
  end

  private

  def validate_test_directory!(dir)
    # Ensure the path contains expected test markers
    unless dir.include?("tmp") || dir.include?("test") || dir.include?("spec")
      raise "Unsafe directory for test cleanup: #{dir}"
    end

    # Ensure it's not a system directory
    dangerous_paths = ["/", "/home", "/Users", "/usr", "/var", "/etc", "/opt"]
    if dangerous_paths.any? { |p| File.expand_path(dir) == p }
      raise "Refusing to operate on system directory: #{dir}"
    end
  end

  def create_session(session_id, valid_config: true, yaml_error: false, bad_alias: false)
    # Create session in the sessions directory
    session_dir = ClaudeSwarm.joined_sessions_dir("test_project", session_id)
    FileUtils.mkdir_p(session_dir)

    # Create config.yml
    config_file = File.join(session_dir, "config.yml")

    if valid_config
      config_content = <<~YAML
        version: 1
        swarm:
          name: "Test Swarm"
          main: lead
          instances:
            lead:
              description: "Lead developer"
              directory: "."
      YAML
      File.write(config_file, config_content)
    elsif yaml_error
      # Invalid YAML syntax
      File.write(config_file, "invalid: yaml: syntax: error")
    elsif bad_alias
      # YAML with undefined alias
      config_content = <<~YAML
        version: 1
        swarm:
          name: "Test Swarm"
          main: lead
          instances:
            lead:
              description: *undefined_alias
      YAML
      File.write(config_file, config_content)
    end

    # Create session.log.json for cost calculation
    log_file = File.join(session_dir, "session.log.json")
    log_content = [
      {
        "timestamp" => Time.now.to_s,
        "type" => "task",
        "instance" => "lead",
        "model" => "claude-3.5-sonnet",
        "input_tokens" => 100,
        "output_tokens" => 200,
        "cost" => 0.0015,
      },
    ]
    # Write as JSONL format (newline-delimited JSON)
    File.write(log_file, log_content.map(&:to_json).join("\n"))

    # Create session_metadata.json
    metadata_file = File.join(session_dir, "session_metadata.json")
    metadata = {
      "session_id" => session_id,
      "start_time" => Time.now.to_s,
    }.to_json
    File.write(metadata_file, metadata)

    session_dir
  end
end
