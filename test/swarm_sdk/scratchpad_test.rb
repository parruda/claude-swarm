# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ScratchpadTest < Minitest::Test
    def setup
      @scratchpad = Tools::Stores::Scratchpad.new
    end

    def test_write_creates_entry_with_metadata
      entry = @scratchpad.write(
        file_path: "test/example",
        content: "Hello, world!",
        title: "Test entry",
      )

      assert_kind_of(Tools::Stores::Scratchpad::Entry, entry)
      assert_equal("Hello, world!", entry.content)
      assert_equal("Test entry", entry.title)
      assert_equal(13, entry.size) # "Hello, world!" is 13 bytes
      assert_instance_of(Time, entry.created_at)
    end

    def test_write_updates_existing_entry
      @scratchpad.write(file_path: "test/example", content: "First", title: "First")
      entry = @scratchpad.write(file_path: "test/example", content: "Second", title: "Updated")

      assert_equal("Second", entry.content)
      assert_equal("Updated", entry.title)
      assert_equal(6, entry.size)
    end

    def test_write_tracks_total_size
      @scratchpad.write(file_path: "a", content: "x" * 100, title: "A")
      @scratchpad.write(file_path: "b", content: "y" * 200, title: "B")

      assert_equal(300, @scratchpad.total_size)
    end

    def test_write_updates_total_size_when_overwriting
      @scratchpad.write(file_path: "test", content: "x" * 100, title: "First")

      assert_equal(100, @scratchpad.total_size)

      @scratchpad.write(file_path: "test", content: "y" * 50, title: "Second")

      assert_equal(50, @scratchpad.total_size)
    end

    def test_write_requires_file_path
      error = assert_raises(ArgumentError) do
        @scratchpad.write(file_path: "", content: "test", title: "Test")
      end
      assert_match(/file_path is required/, error.message)

      error = assert_raises(ArgumentError) do
        @scratchpad.write(file_path: nil, content: "test", title: "Test")
      end
      assert_match(/file_path is required/, error.message)
    end

    def test_write_requires_content
      error = assert_raises(ArgumentError) do
        @scratchpad.write(file_path: "test", content: nil, title: "Test")
      end
      assert_match(/content is required/, error.message)
    end

    def test_write_requires_title
      error = assert_raises(ArgumentError) do
        @scratchpad.write(file_path: "test", content: "test", title: "")
      end
      assert_match(/title is required/, error.message)

      error = assert_raises(ArgumentError) do
        @scratchpad.write(file_path: "test", content: "test", title: nil)
      end
      assert_match(/title is required/, error.message)
    end

    def test_write_rejects_oversized_entry
      large_content = "x" * (Tools::Stores::Scratchpad::MAX_ENTRY_SIZE + 1)

      error = assert_raises(ArgumentError) do
        @scratchpad.write(file_path: "test", content: large_content, title: "Too big")
      end
      assert_match(/exceeds maximum size/, error.message)
      assert_match(/1.0MB/, error.message)
    end

    def test_write_rejects_when_total_size_exceeded
      # Fill up scratchpad with multiple 1MB entries (just under MAX_TOTAL_SIZE)
      # MAX_TOTAL_SIZE is 100MB, MAX_ENTRY_SIZE is 1MB
      # So we can fit 100 entries of 1MB each, but not 101
      entries_count = (Tools::Stores::Scratchpad::MAX_TOTAL_SIZE / Tools::Stores::Scratchpad::MAX_ENTRY_SIZE).floor
      entry_size = Tools::Stores::Scratchpad::MAX_ENTRY_SIZE - 1000 # Leave some room

      entries_count.times do |i|
        @scratchpad.write(file_path: "entry_#{i}", content: "x" * entry_size, title: "Entry #{i}")
      end

      # Try to add one more entry that would exceed total limit
      error = assert_raises(ArgumentError) do
        @scratchpad.write(file_path: "overflow", content: "y" * entry_size, title: "Overflow")
      end
      assert_match(/Scratchpad full/, error.message)
      assert_match(/100.0MB limit/, error.message)
    end

    def test_read_returns_content
      @scratchpad.write(file_path: "test/path", content: "Expected content", title: "Test")

      content = @scratchpad.read(file_path: "test/path")

      assert_equal("Expected content", content)
    end

    def test_read_requires_file_path
      error = assert_raises(ArgumentError) do
        @scratchpad.read(file_path: "")
      end
      assert_match(/file_path is required/, error.message)

      error = assert_raises(ArgumentError) do
        @scratchpad.read(file_path: nil)
      end
      assert_match(/file_path is required/, error.message)
    end

    def test_read_raises_for_missing_path
      error = assert_raises(ArgumentError) do
        @scratchpad.read(file_path: "nonexistent")
      end
      assert_match(%r{scratchpad://nonexistent not found}, error.message)
    end

    def test_list_returns_all_entries_when_no_prefix
      @scratchpad.write(file_path: "a/1", content: "A1", title: "Entry A1")
      @scratchpad.write(file_path: "a/2", content: "A2", title: "Entry A2")
      @scratchpad.write(file_path: "b/1", content: "B1", title: "Entry B1")

      entries = @scratchpad.list

      assert_equal(3, entries.size)
      assert_equal(["a/1", "a/2", "b/1"], entries.map { |e| e[:path] })
      assert_equal(["Entry A1", "Entry A2", "Entry B1"], entries.map { |e| e[:title] })
    end

    def test_list_filters_by_prefix
      @scratchpad.write(file_path: "parallel/batch1/task_0", content: "T0", title: "Task 0")
      @scratchpad.write(file_path: "parallel/batch1/task_1", content: "T1", title: "Task 1")
      @scratchpad.write(file_path: "analysis/report", content: "R", title: "Report")

      entries = @scratchpad.list(prefix: "parallel/batch1/")

      assert_equal(2, entries.size)
      assert_equal(["parallel/batch1/task_0", "parallel/batch1/task_1"], entries.map { |e| e[:path] })
    end

    def test_list_returns_empty_for_no_matches
      @scratchpad.write(file_path: "a/1", content: "A1", title: "Entry A1")

      entries = @scratchpad.list(prefix: "b/")

      assert_equal(0, entries.size)
    end

    def test_list_returns_metadata
      @scratchpad.write(file_path: "test", content: "x" * 100, title: "Test entry")

      entries = @scratchpad.list

      assert_equal(1, entries.size)
      entry = entries.first

      assert_equal("test", entry[:path])
      assert_equal("Test entry", entry[:title])
      assert_equal(100, entry[:size])
      assert_instance_of(Time, entry[:created_at])
    end

    def test_list_sorts_by_path
      @scratchpad.write(file_path: "z", content: "Z", title: "Z")
      @scratchpad.write(file_path: "a", content: "A", title: "A")
      @scratchpad.write(file_path: "m", content: "M", title: "M")

      entries = @scratchpad.list

      assert_equal(["a", "m", "z"], entries.map { |e| e[:path] })
    end

    def test_clear_removes_all_entries
      @scratchpad.write(file_path: "a", content: "A", title: "A")
      @scratchpad.write(file_path: "b", content: "B", title: "B")

      @scratchpad.clear

      assert_equal(0, @scratchpad.size)
      assert_equal(0, @scratchpad.total_size)
      assert_raises(ArgumentError) { @scratchpad.read(file_path: "a") }
    end

    def test_size_returns_entry_count
      assert_equal(0, @scratchpad.size)

      @scratchpad.write(file_path: "a", content: "A", title: "A")

      assert_equal(1, @scratchpad.size)

      @scratchpad.write(file_path: "b", content: "B", title: "B")

      assert_equal(2, @scratchpad.size)

      @scratchpad.write(file_path: "a", content: "Updated", title: "Updated")

      assert_equal(2, @scratchpad.size) # Overwrite doesn't increase count
    end

    def test_multibyte_characters_counted_correctly
      # "😀" is 4 bytes in UTF-8
      content = "😀" * 10 # 40 bytes
      @scratchpad.write(file_path: "emoji", content: content, title: "Emoji test")

      assert_equal(40, @scratchpad.total_size)
    end

    def test_write_with_nil_file_path_raises_error
      error = assert_raises(ArgumentError) do
        @scratchpad.write(file_path: nil, content: "test", title: "Test")
      end
      assert_match(/file_path is required/, error.message)
    end

    def test_read_with_nil_file_path_raises_error
      error = assert_raises(ArgumentError) do
        @scratchpad.read(file_path: nil)
      end
      assert_match(/file_path is required/, error.message)
    end

    def test_list_with_nil_prefix
      @scratchpad.write(file_path: "a/1", content: "A1", title: "Entry A1")
      @scratchpad.write(file_path: "b/1", content: "B1", title: "Entry B1")

      entries = @scratchpad.list(prefix: nil)

      assert_equal(2, entries.size)
    end

    def test_list_with_empty_string_prefix
      @scratchpad.write(file_path: "a/1", content: "A1", title: "Entry A1")
      @scratchpad.write(file_path: "b/1", content: "B1", title: "Entry B1")

      entries = @scratchpad.list(prefix: "")

      # Empty prefix should match all entries
      assert_equal(2, entries.size)
    end
  end
end
