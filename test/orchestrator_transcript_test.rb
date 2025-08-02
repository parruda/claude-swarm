# frozen_string_literal: true

require "test_helper"
require "tempfile"

class OrchestratorTranscriptTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @session_path = File.join(@tmpdir, "session")
    FileUtils.mkdir_p(@session_path)
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path
    ENV["CLAUDE_SWARM_ROOT_DIR"] = @tmpdir

    # Create mock config
    @config = mock_config
    @generator = mock_generator
    @settings_generator = mock_settings_generator
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
    ENV.delete("CLAUDE_SWARM_ROOT_DIR")
  end

  def test_transcript_tailing_waits_for_path_file
    orchestrator = ClaudeSwarm::Orchestrator.new(@config, @generator)
    orchestrator.instance_variable_set(:@session_path, @session_path)

    # Start transcript tailing in background
    thread = orchestrator.send(:start_transcript_tailing)

    # Thread should be waiting for path file
    sleep(0.1)

    assert_predicate(thread, :alive?)

    # Create path file
    path_file = File.join(@session_path, "main_instance_transcript.path")
    transcript_file = File.join(@tmpdir, "transcript.jsonl")
    File.write(path_file, transcript_file)

    # Create transcript file
    File.write(transcript_file, "")

    # Thread should still be alive (tailing)
    sleep(0.1)

    assert_predicate(thread, :alive?)

    # Clean up thread
    thread.terminate
    thread.join(1)
  end

  def test_transcript_tailing_processes_entries
    orchestrator = ClaudeSwarm::Orchestrator.new(@config, @generator)
    orchestrator.instance_variable_set(:@session_path, @session_path)

    # Create path file pointing to transcript FIRST
    transcript_file = File.join(@tmpdir, "transcript.jsonl")
    path_file = File.join(@session_path, "main_instance_transcript.path")
    File.write(path_file, transcript_file)

    # Create empty transcript file
    File.write(transcript_file, "")

    # Start transcript tailing
    thread = orchestrator.send(:start_transcript_tailing)
    
    # Wait for thread to be ready
    sleep(0.5)
    
    # Now append entries to the file
    File.open(transcript_file, "a") do |f|
      create_transcript_entries.each do |entry|
        f.puts(entry)
      end
    end

    # Give thread time to process entries - wait up to 2 seconds for file to appear
    session_json = File.join(@session_path, "session.log.json")
    10.times do
      break if File.exist?(session_json)
      sleep(0.2)
    end

    assert_path_exists(session_json)

    # Read and verify entries
    entries = File.readlines(session_json).map { |line| JSON.parse(line) }

    assert_operator(entries.size, :>=, 2)

    # Verify format
    first_entry = entries.first

    assert_equal("lead", first_entry["instance"])
    assert_equal("main", first_entry["instance_id"])
    assert(first_entry["timestamp"])
    assert_equal("transcript", first_entry["event"]["type"])
    assert_equal("main_instance", first_entry["event"]["source"])
    assert(first_entry["event"]["data"])

    # Clean up thread
    thread.terminate
    thread.join(1)
  end

  def test_transcript_tailing_handles_new_entries
    orchestrator = ClaudeSwarm::Orchestrator.new(@config, @generator)
    orchestrator.instance_variable_set(:@session_path, @session_path)

    # Create empty transcript file
    transcript_file = File.join(@tmpdir, "transcript.jsonl")
    File.write(transcript_file, "")

    # Create path file
    path_file = File.join(@session_path, "main_instance_transcript.path")
    File.write(path_file, transcript_file)

    # Start transcript tailing
    thread = orchestrator.send(:start_transcript_tailing)

    # Give thread time to start
    sleep(0.2)

    # Append new entry to transcript
    File.open(transcript_file, "a") do |f|
      f.puts('{"type":"user","message":"test","timestamp":"2025-01-01T00:00:00Z"}')
    end

    # Give thread time to process - wait up to 2 seconds for file to appear
    session_json = File.join(@session_path, "session.log.json")
    10.times do
      break if File.exist?(session_json)
      sleep(0.2)
    end

    assert_path_exists(session_json)

    entries = File.readlines(session_json).map { |line| JSON.parse(line) }

    assert_equal(1, entries.size)
    assert_equal("user", entries.first["event"]["data"]["type"])

    # Clean up thread
    thread.terminate
    thread.join(1)
  end

  def test_transcript_tailing_handles_json_parse_errors
    orchestrator = ClaudeSwarm::Orchestrator.new(@config, @generator)
    orchestrator.instance_variable_set(:@session_path, @session_path)

    # Create transcript with invalid JSON
    transcript_file = File.join(@tmpdir, "transcript.jsonl")
    File.write(transcript_file, "invalid json\n")

    # Create path file
    path_file = File.join(@session_path, "main_instance_transcript.path")
    File.write(path_file, transcript_file)

    # Start transcript tailing - should not crash
    thread = orchestrator.send(:start_transcript_tailing)

    # Give thread time to process
    sleep(0.2)

    # Thread should still be alive despite error
    assert_predicate(thread, :alive?)

    # Add valid entry after invalid one
    File.open(transcript_file, "a") do |f|
      f.puts('{"type":"valid","timestamp":"2025-01-01T00:00:00Z"}')
    end

    sleep(0.2)

    # Valid entry should be processed
    session_json = File.join(@session_path, "session.log.json")
    if File.exist?(session_json)
      entries = File.readlines(session_json).map { |line| JSON.parse(line) }

      assert_equal(1, entries.size)
      assert_equal("valid", entries.first["event"]["data"]["type"])
    end

    # Clean up thread
    thread.terminate
    thread.join(1)
  end

  def test_cleanup_transcript_thread
    orchestrator = ClaudeSwarm::Orchestrator.new(@config, @generator)
    orchestrator.instance_variable_set(:@session_path, @session_path)

    # Create necessary files for thread to start
    transcript_file = File.join(@tmpdir, "transcript.jsonl")
    File.write(transcript_file, "")
    path_file = File.join(@session_path, "main_instance_transcript.path")
    File.write(path_file, transcript_file)

    # Start thread
    thread = orchestrator.send(:start_transcript_tailing)
    orchestrator.instance_variable_set(:@transcript_thread, thread)

    # Thread should be alive
    sleep(0.1)

    assert_predicate(thread, :alive?)

    # Cleanup should terminate thread
    orchestrator.send(:cleanup_transcript_thread)

    # Thread should be terminated
    refute_predicate(thread, :alive?)
  end

  def test_convert_transcript_to_session_format
    orchestrator = ClaudeSwarm::Orchestrator.new(@config, @generator)
    orchestrator.instance_variable_set(:@session_path, @session_path)

    transcript_entry = {
      "type" => "user",
      "message" => "test message",
      "timestamp" => "2025-01-01T00:00:00Z",
      "extra" => "data",
    }

    result = orchestrator.send(:convert_transcript_to_session_format, transcript_entry)

    assert_equal("lead", result[:instance])
    assert_equal("main", result[:instance_id])
    assert_equal("2025-01-01T00:00:00Z", result[:timestamp])
    assert_equal("transcript", result[:event][:type])
    assert_equal("main_instance", result[:event][:source])
    assert_equal(transcript_entry, result[:event][:data])
  end

  def test_convert_transcript_without_timestamp
    orchestrator = ClaudeSwarm::Orchestrator.new(@config, @generator)
    orchestrator.instance_variable_set(:@session_path, @session_path)

    transcript_entry = {
      "type" => "user",
      "message" => "test message",
    }

    result = orchestrator.send(:convert_transcript_to_session_format, transcript_entry)

    # Should have generated timestamp
    assert(result[:timestamp])
    assert_match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, result[:timestamp])
  end

  private

  def mock_config
    config = Minitest::Mock.new
    config.expect(:main_instance, "lead")
    config.expect(:main_instance, "lead")
    config.expect(:main_instance, "lead")
    config.expect(:main_instance, "lead")
    config.expect(:main_instance, "lead")
    config.expect(:main_instance, "lead")
    config.expect(:main_instance, "lead")
    config.expect(:main_instance, "lead")
    # Add instances expectation for orchestrator initialization
    config.expect(:instances, {})
    config.expect(:instances, {})
    config.expect(:instances, {})
    config.expect(:instances, {})
    config.expect(:instances, {})
    config.expect(:instances, {})
    config.expect(:instances, {})
    config
  end

  def mock_generator
    Minitest::Mock.new
  end

  def mock_settings_generator
    Minitest::Mock.new
  end

  def create_transcript_entries
    [
      '{"type":"user","message":"Hello","timestamp":"2025-01-01T00:00:00Z"}',
      '{"type":"assistant","message":"Hi there","timestamp":"2025-01-01T00:00:01Z"}',
    ]
  end
end
