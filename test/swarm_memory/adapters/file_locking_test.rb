# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class FileLockingTest < Minitest::Test
  def setup
    @temp_dir = File.join(Dir.tmpdir, "test-file-locking-#{SecureRandom.hex(8)}")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  def test_lock_file_is_created
    adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)
    adapter.write(file_path: "test.md", content: "test", title: "Test")

    # Lock file should exist in directory
    lock_file = File.join(@temp_dir, ".lock")

    assert_path_exists(lock_file, "Lock file should be created")
  end

  def test_concurrent_writes_in_same_process
    adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)
    storage = SwarmMemory::Core::Storage.new(adapter: adapter)

    # Create threads that write concurrently
    threads = 10.times.map do |i|
      Thread.new do
        5.times do |j|
          storage.write(
            file_path: "thread-#{i}/entry-#{j}.md",
            content: "Thread #{i}, Entry #{j}",
            title: "Entry #{i}-#{j}",
            metadata: { "thread" => i, "entry" => j },
          )
        end
      end
    end

    # Wait for all threads
    threads.each(&:join)

    # Verify all entries were written
    entries = adapter.list

    assert_equal(50, entries.size, "All 50 entries should be written")

    # Verify no corruption
    entries.each do |entry|
      content = adapter.read(file_path: entry[:path])

      assert_match(/Thread \d+, Entry \d+/, content, "Content should be intact")
    end
  end

  def test_write_and_delete_concurrency
    adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)

    # Write initial entries
    10.times do |i|
      adapter.write(file_path: "entry-#{i}.md", content: "content #{i}", title: "Entry #{i}")
    end

    # Concurrently write and delete
    threads = []

    # Writer thread
    threads << Thread.new do
      10.times do |i|
        adapter.write(file_path: "new-#{i}.md", content: "new #{i}", title: "New #{i}")
        sleep(0.001)
      end
    end

    # Deleter thread
    threads << Thread.new do
      5.times do |i|
        adapter.delete(file_path: "entry-#{i}.md")
        sleep(0.001)
      end
    end

    threads.each(&:join)

    # Verify expected state
    entries = adapter.list
    # Should have 5 original (not deleted) + 10 new = 15
    assert_equal(15, entries.size)
  end

  def test_cross_process_writes_no_corruption
    # Skip if fork not available (e.g., Windows)
    skip("Fork not available") unless Process.respond_to?(:fork)

    # Create multiple processes that write simultaneously
    pids = []

    5.times do |i|
      pids << fork do
        adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)

        10.times do |j|
          adapter.write(
            file_path: "process-#{i}/entry-#{j}.md",
            content: "Process #{i}, Entry #{j}",
            title: "Entry #{i}-#{j}",
            metadata: { "process" => i, "entry" => j },
          )
          sleep(0.01) # Small delay to increase chance of conflicts
        end

        exit(0)
      end
    end

    # Wait for all processes
    pids.each { |pid| Process.wait(pid) }

    # Verify all entries were written correctly
    adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)
    entries = adapter.list

    assert_equal(50, entries.size, "All 50 entries should be written across processes")

    # Verify no corrupted files
    corrupted = 0
    entries.each do |entry|
      content = adapter.read(file_path: entry[:path])

      assert_match(/Process \d+, Entry \d+/, content)
    rescue StandardError
      corrupted += 1
    end

    assert_equal(0, corrupted, "No files should be corrupted")
  end

  def test_lock_is_released_on_error
    adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)

    # Try to write with invalid data (should raise error)
    assert_raises(ArgumentError) do
      adapter.write(file_path: "test.md", content: "x" * (SwarmMemory::Adapters::Base::MAX_ENTRY_SIZE + 1), title: "Too Large")
    end

    # Lock should be released - subsequent write should work
    adapter.write(file_path: "valid.md", content: "valid content", title: "Valid")

    # Verify it was written
    content = adapter.read(file_path: "valid.md")

    assert_equal("valid content", content)
  end

  def test_clear_with_file_locking
    adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)

    # Write some entries
    5.times do |i|
      adapter.write(file_path: "entry-#{i}.md", content: "content #{i}", title: "Entry #{i}")
    end

    # Clear should acquire lock
    adapter.clear

    # Verify all files deleted
    entries = adapter.list

    assert_equal(0, entries.size)
  end

  def test_semaphore_acquire_blocks_properly
    adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)
    write_order = []

    # Two threads writing to same path
    threads = []

    threads << Thread.new do
      adapter.write(file_path: "shared.md", content: "thread 1", title: "Thread 1")
      write_order << 1
    end

    # Small delay to ensure thread 1 gets lock first
    sleep(0.01)

    threads << Thread.new do
      adapter.write(file_path: "shared.md", content: "thread 2", title: "Thread 2")
      write_order << 2
    end

    threads.each(&:join)

    # Verify sequential execution (write_order should be [1, 2])
    assert_equal([1, 2], write_order)

    # Verify final content is from thread 2 (last write wins)
    content = adapter.read(file_path: "shared.md")

    assert_equal("thread 2", content)
  end
end
