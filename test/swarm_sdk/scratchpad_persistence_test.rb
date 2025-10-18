# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "json"

module SwarmSDK
  class ScratchpadPersistenceTest < Minitest::Test
    def setup
      @temp_dir = Dir.mktmpdir
      @persist_path = File.join(@temp_dir, "scratchpad.json")
    end

    def teardown
      FileUtils.rm_rf(@temp_dir)
    end

    def test_scratchpad_persists_on_write
      scratchpad = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      scratchpad.write(file_path: "test/path", content: "Test content", title: "Test")

      assert_path_exists(@persist_path)

      # Verify JSON structure
      data = JSON.parse(File.read(@persist_path))

      assert_equal(1, data["version"])
      assert_equal(12, data["total_size"]) # "Test content" is 12 bytes
      assert(data["entries"]["test/path"])
      assert_equal("Test content", data["entries"]["test/path"]["content"])
      assert_equal("Test", data["entries"]["test/path"]["title"])
    end

    def test_scratchpad_loads_from_existing_file
      # Create a scratchpad and write data
      scratchpad1 = Tools::Stores::Scratchpad.new(persist_to: @persist_path)
      scratchpad1.write(file_path: "foo", content: "Hello", title: "Greeting")
      scratchpad1.write(file_path: "bar", content: "World", title: "Place")

      # Create a new scratchpad instance - should load existing data
      scratchpad2 = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      assert_equal("Hello", scratchpad2.read(file_path: "foo"))
      assert_equal("World", scratchpad2.read(file_path: "bar"))
      assert_equal(10, scratchpad2.total_size) # "Hello" (5) + "World" (5)
    end

    def test_scratchpad_updates_existing_entry
      scratchpad = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      scratchpad.write(file_path: "test", content: "Original", title: "Title")
      scratchpad.write(file_path: "test", content: "Updated", title: "New Title")

      # Load from file to verify
      scratchpad2 = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      assert_equal("Updated", scratchpad2.read(file_path: "test"))
      assert_equal(7, scratchpad2.total_size) # "Updated" is 7 bytes
    end

    def test_scratchpad_handles_multiple_entries
      scratchpad = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      # Write multiple entries
      10.times do |i|
        scratchpad.write(
          file_path: "entry_#{i}",
          content: "Content #{i}",
          title: "Title #{i}",
        )
      end

      # Load and verify
      scratchpad2 = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      10.times do |i|
        assert_equal("Content #{i}", scratchpad2.read(file_path: "entry_#{i}"))
      end
    end

    def test_scratchpad_preserves_metadata
      scratchpad = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      before_time = Time.now - 1 # Allow 1 second buffer for serialization
      scratchpad.write(file_path: "test", content: "Test content", title: "Test Title")
      after_time = Time.now + 1 # Allow 1 second buffer for serialization

      # Load and verify metadata
      scratchpad2 = Tools::Stores::Scratchpad.new(persist_to: @persist_path)
      entries = scratchpad2.list

      entry = entries.first

      assert_equal("test", entry[:path])
      assert_equal("Test Title", entry[:title])
      assert_equal(12, entry[:size])
      assert_operator(entry[:created_at], :>=, before_time)
      assert_operator(entry[:created_at], :<=, after_time)
    end

    def test_scratchpad_handles_corrupted_file
      # Write invalid JSON
      File.write(@persist_path, "not valid json")

      # Should not raise error, should start with empty scratchpad
      scratchpad = nil
      _out, err = capture_io do
        scratchpad = Tools::Stores::Scratchpad.new(persist_to: @persist_path)
      end

      assert_match(/Warning.*Failed to load scratchpad/, err)
      assert_equal(0, scratchpad.size)
      assert_equal(0, scratchpad.total_size)
    end

    def test_scratchpad_creates_directory_if_needed
      deep_path = File.join(@temp_dir, "nested", "deep", "path", "scratchpad.json")
      scratchpad = Tools::Stores::Scratchpad.new(persist_to: deep_path)

      scratchpad.write(file_path: "test", content: "Test", title: "Test")

      assert_path_exists(deep_path)
    end

    def test_scratchpad_without_persistence_does_not_create_file
      scratchpad = Tools::Stores::Scratchpad.new # No persist_to

      scratchpad.write(file_path: "test", content: "Test", title: "Test")

      refute_path_exists(@persist_path)
    end

    def test_scratchpad_persistence_is_atomic
      scratchpad = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      scratchpad.write(file_path: "test", content: "Test content", title: "Test")

      # Temp file should not exist after write completes
      refute_path_exists("#{@persist_path}.tmp")
    end

    def test_scratchpad_handles_unicode_content_persistence
      scratchpad = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      unicode_content = "Hello 🌍! Привет мир! 你好世界!"
      scratchpad.write(file_path: "unicode", content: unicode_content, title: "Unicode Test")

      # Load and verify
      scratchpad2 = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      assert_equal(unicode_content, scratchpad2.read(file_path: "unicode"))
    end

    def test_scratchpad_persistence_with_complex_paths
      scratchpad = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      paths = [
        "parallel/batch_a/task_0",
        "analysis/performance/report",
        "research/frameworks/rails/patterns",
      ]

      paths.each_with_index do |path, i|
        scratchpad.write(file_path: path, content: "Content #{i}", title: "Title #{i}")
      end

      # Load and verify
      scratchpad2 = Tools::Stores::Scratchpad.new(persist_to: @persist_path)

      paths.each_with_index do |path, i|
        assert_equal("Content #{i}", scratchpad2.read(file_path: path))
      end
    end
  end
end
