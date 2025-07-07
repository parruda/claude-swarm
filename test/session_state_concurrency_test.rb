# frozen_string_literal: true

require "test_helper"
class SessionStateConcurrencyTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir
    @session_path = @test_dir
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def test_concurrent_instance_state_writes
    # Simulate concurrent writes from multiple processes
    instances = ["lead_abc123", "frontend_def456", "backend_ghi789", "worker1_jkl012", "worker2_mno345"]

    threads = instances.map do |instance_id|
      Thread.new do
        instance_name = instance_id.split("_").first

        # Each thread writes its state multiple times
        5.times do |i|
          session_id = "#{instance_name}-#{SecureRandom.uuid}-#{i}"

          state_dir = File.join(@session_path, "state")
          FileUtils.mkdir_p(state_dir)

          state_file = File.join(state_dir, "#{instance_id}.json")
          state_data = {
            instance_name: instance_name,
            instance_id: instance_id,
            claude_session_id: session_id,
            status: "active",
            updated_at: Time.now.iso8601,
          }

          # Use file locking to ensure thread safety
          File.open(state_file, File::RDWR | File::CREAT, 0o644) do |file|
            file.flock(File::LOCK_EX)
            file.truncate(0)
            file.write(JSON.pretty_generate(state_data))
            file.flush
            file.flock(File::LOCK_UN)
          end

          sleep(0.001) # Small delay to increase chance of conflicts
        end
      end
    end

    # Wait for all threads to complete
    threads.each(&:join)

    # Verify all states were written
    instances.each do |instance_id|
      instance_name = instance_id.split("_").first

      # Verify the state file exists
      state_file = File.join(@session_path, "state", "#{instance_id}.json")

      assert_path_exists(state_file)

      # Verify state file is valid JSON
      state_data = JSON.parse(File.read(state_file))

      assert_equal(instance_name, state_data["instance_name"])
      assert_equal(instance_id, state_data["instance_id"])
      assert(state_data["claude_session_id"])
      assert_equal("active", state_data["status"])
      assert(state_data["updated_at"])
    end
  end

  def test_state_directory_creation
    # Test that state directory is created if it doesn't exist
    refute(Dir.exist?(File.join(@session_path, "state")))

    # Write a state file
    state_dir = File.join(@session_path, "state")
    FileUtils.mkdir_p(state_dir)

    state_file = File.join(state_dir, "test_instance_xyz789.json")
    state_data = {
      instance_name: "test_instance",
      instance_id: "test_instance_xyz789",
      claude_session_id: "test_session_id",
      status: "active",
      updated_at: Time.now.iso8601,
    }

    File.write(state_file, JSON.pretty_generate(state_data))

    assert(Dir.exist?(File.join(@session_path, "state")))
    assert_path_exists(state_file)
  end

  def test_invalid_state_files_are_skipped
    # Create state directory and write invalid JSON
    state_dir = File.join(@session_path, "state")
    FileUtils.mkdir_p(state_dir)
    File.write(File.join(state_dir, "invalid.json"), "not valid json")

    # Also write a valid state file
    valid_state_file = File.join(state_dir, "valid_abc123.json")
    valid_state_data = {
      instance_name: "valid",
      instance_id: "valid_abc123",
      claude_session_id: "valid_session_id",
      status: "active",
      updated_at: Time.now.iso8601,
    }
    File.write(valid_state_file, JSON.pretty_generate(valid_state_data))

    # Try to read all state files - should skip invalid ones
    states = {}
    Dir.glob(File.join(state_dir, "*.json")).each do |state_file|
      data = JSON.parse(File.read(state_file))
      states[data["instance_id"]] = data
    rescue StandardError
      # Skip invalid files
    end

    # Should have loaded the valid state
    assert_equal(1, states.size)
    assert_equal("valid_abc123", states.keys.first)
    assert_equal("valid_session_id", states["valid_abc123"]["claude_session_id"])
  end
end
