# frozen_string_literal: true

require "test_helper"
require "tempfile"

class OrchestratorTranscriptTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @session_path = File.join(@tmpdir, "session")
    FileUtils.mkdir_p(@session_path)
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path

    # Create mock config
    @config = mock_config
    @generator = mock_generator
    @settings_generator = mock_settings_generator
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
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
    assert_equal("request", first_entry["event"]["type"])
    assert_equal("user", first_entry["event"]["from_instance"])
    assert(first_entry["event"]["prompt"])

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
    assert_equal("request", entries.first["event"]["type"])

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
    assert_equal("request", result[:event][:type])
    assert_equal("user", result[:event][:from_instance])
    assert_equal("test message", result[:event][:prompt])
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
    assert_equal("request", result[:event][:type])
    assert_equal("test message", result[:event][:prompt])
  end

  def test_transcript_tailing_skips_summary_entries
    orchestrator = ClaudeSwarm::Orchestrator.new(@config, @generator)
    orchestrator.instance_variable_set(:@session_path, @session_path)

    # Create transcript file with summary entries
    transcript_file = File.join(@tmpdir, "transcript.jsonl")
    File.open(transcript_file, "w") do |f|
      f.puts('{"type":"summary","title":"Test Conversation","timestamp":"2025-01-01T00:00:00Z"}')
      f.puts('{"type":"user","message":"Hello","timestamp":"2025-01-01T00:00:01Z"}')
      f.puts('{"type":"summary","title":"Updated Title","timestamp":"2025-01-01T00:00:02Z"}')
      f.puts('{"type":"assistant","message":"Hi there","timestamp":"2025-01-01T00:00:03Z"}')
    end

    # Create path file
    path_file = File.join(@session_path, "main_instance_transcript.path")
    File.write(path_file, transcript_file)

    # Start transcript tailing
    thread = orchestrator.send(:start_transcript_tailing)

    # Give thread time to process
    sleep(0.5)

    # Check session.log.json
    session_json = File.join(@session_path, "session.log.json")

    assert_path_exists(session_json)

    entries = File.readlines(session_json).map { |line| JSON.parse(line) }

    # Should only have 2 entries (user and assistant), not the summary entries
    assert_equal(2, entries.size)

    # Verify the entries are the correct ones
    assert_equal("request", entries[0]["event"]["type"])
    assert_equal("Hello", entries[0]["event"]["prompt"])

    assert_equal("assistant", entries[1]["event"]["type"])
    assert_equal("Hi there", entries[1]["event"]["message"]["content"][0]["text"])

    # Clean up thread
    thread.terminate
    thread.join(1)
  end

  def test_transcript_tailing_reads_from_beginning
    orchestrator = ClaudeSwarm::Orchestrator.new(@config, @generator)
    orchestrator.instance_variable_set(:@session_path, @session_path)

    # Create transcript file with existing entries
    transcript_file = File.join(@tmpdir, "transcript.jsonl")
    File.open(transcript_file, "w") do |f|
      f.puts('{"type":"user","message":"First entry","timestamp":"2025-01-01T00:00:00Z"}')
      f.puts('{"type":"assistant","message":"Second entry","timestamp":"2025-01-01T00:00:01Z"}')
    end

    # Create path file
    path_file = File.join(@session_path, "main_instance_transcript.path")
    File.write(path_file, transcript_file)

    # Start transcript tailing - should read from beginning
    thread = orchestrator.send(:start_transcript_tailing)

    # Give thread time to process existing entries
    sleep(0.5)

    # Check that existing entries were captured
    session_json = File.join(@session_path, "session.log.json")

    assert_path_exists(session_json)

    entries = File.readlines(session_json).map { |line| JSON.parse(line) }

    # Should have both existing entries
    assert_equal(2, entries.size)
    assert_equal("First entry", entries[0]["event"]["prompt"])
    assert_equal("Second entry", entries[1]["event"]["message"]["content"][0]["text"])

    # Now add a new entry
    File.open(transcript_file, "a") do |f|
      f.puts('{"type":"user","message":"Third entry","timestamp":"2025-01-01T00:00:02Z"}')
    end

    # Give thread time to process new entry
    sleep(0.5)

    # Re-read entries
    entries = File.readlines(session_json).map { |line| JSON.parse(line) }

    # Should now have 3 entries total
    assert_equal(3, entries.size)
    assert_equal("Third entry", entries[2]["event"]["prompt"])

    # Clean up thread
    thread.terminate
    thread.join(1)
  end

  private

  def mock_config
    config = Minitest::Mock.new
    # Expect main_instance to be called multiple times (once per test that uses it)
    8.times { config.expect(:main_instance, "lead") }
    # Expect instances to be called multiple times for orchestrator initialization
    7.times { config.expect(:instances, {}) }
    # Expect base_dir to be called for session path generation
    7.times { config.expect(:base_dir, Dir.pwd) }
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
