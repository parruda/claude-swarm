# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class FilesystemAdapterTest < Minitest::Test
  def setup
    @temp_dir = File.join(Dir.tmpdir, "test-adapter-#{SecureRandom.hex(8)}")
    @adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  def test_write_and_read
    entry = @adapter.write(
      file_path: "test/entry.md",
      content: "test content",
      title: "Test Entry",
    )

    assert_equal("test content", entry.content)
    assert_equal("Test Entry", entry.title)
    assert_equal(12, entry.size)

    content = @adapter.read(file_path: "test/entry.md")

    assert_equal("test content", content)
  end

  def test_write_with_embedding
    embedding = Array.new(384) { rand }
    entry = @adapter.write(
      file_path: "test/embedding.md",
      content: "content",
      title: "Test",
      embedding: embedding,
    )

    assert_equal(embedding, entry.embedding)

    full_entry = @adapter.read_entry(file_path: "test/embedding.md")

    # Embeddings are packed/unpacked as floats, so check approximate equality
    assert_equal(384, full_entry.embedding.size)
    embedding.each_with_index do |expected, i|
      assert_in_delta(expected, full_entry.embedding[i], 0.0001, "Embedding mismatch at index #{i}")
    end
  end

  def test_write_persists_to_disk
    @adapter.write(
      file_path: "test/persist.md",
      content: "persistent",
      title: "Test",
    )

    # Check that .md and .yml files were created
    assert_path_exists(File.join(@temp_dir, "test--persist.md"))
    assert_path_exists(File.join(@temp_dir, "test--persist.yml"))

    # Load a new adapter from the same directory
    new_adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: @temp_dir)
    content = new_adapter.read(file_path: "test/persist.md")

    assert_equal("persistent", content)
  end

  def test_delete
    @adapter.write(file_path: "test/delete.md", content: "to delete", title: "Test")

    @adapter.delete(file_path: "test/delete.md")

    error = assert_raises(ArgumentError) do
      @adapter.read(file_path: "test/delete.md")
    end
    assert_match(/not found/, error.message)
  end

  def test_list
    @adapter.write(file_path: "concepts/ruby.md", content: "ruby", title: "Ruby")
    @adapter.write(file_path: "concepts/python.md", content: "python", title: "Python")
    @adapter.write(file_path: "facts/user.md", content: "user", title: "User")

    entries = @adapter.list

    assert_equal(3, entries.size)
    assert_equal(["concepts/python.md", "concepts/ruby.md", "facts/user.md"], entries.map { |e| e[:path] }.sort)
  end

  def test_list_with_prefix
    @adapter.write(file_path: "concepts/ruby.md", content: "ruby", title: "Ruby")
    @adapter.write(file_path: "concepts/python.md", content: "python", title: "Python")
    @adapter.write(file_path: "facts/user.md", content: "user", title: "User")

    entries = @adapter.list(prefix: "concepts")

    assert_equal(2, entries.size)
    assert_equal(["concepts/python.md", "concepts/ruby.md"], entries.map { |e| e[:path] }.sort)
  end

  def test_glob
    @adapter.write(file_path: "concepts/ruby/classes.md", content: "classes", title: "Classes")
    @adapter.write(file_path: "concepts/ruby/modules.md", content: "modules", title: "Modules")
    @adapter.write(file_path: "concepts/python/classes.md", content: "py", title: "Py Classes")

    results = @adapter.glob(pattern: "concepts/ruby/*.md")

    assert_equal(2, results.size)
    assert_includes(results.map { |r| r[:path] }, "concepts/ruby/classes.md")
    assert_includes(results.map { |r| r[:path] }, "concepts/ruby/modules.md")
  end

  def test_grep_files_with_matches
    @adapter.write(file_path: "entry1.md", content: "contains ruby code", title: "Entry 1")
    @adapter.write(file_path: "entry2.md", content: "contains python code", title: "Entry 2")
    @adapter.write(file_path: "entry3.md", content: "no match", title: "Entry 3")

    results = @adapter.grep(pattern: "ruby", output_mode: "files_with_matches")

    assert_equal(1, results.size)
    assert_equal("entry1.md", results.first)
  end

  def test_grep_content
    @adapter.write(file_path: "test.md", content: "line1 ruby\nline2 test\nline3 ruby", title: "Test")

    results = @adapter.grep(pattern: "ruby", output_mode: "content")

    assert_equal(1, results.size)
    assert_equal("test.md", results.first[:path])
    assert_equal(2, results.first[:matches].size)
    assert_equal(1, results.first[:matches].first[:line_number])
  end

  def test_clear
    @adapter.write(file_path: "test1.md", content: "content1", title: "Test 1")
    @adapter.write(file_path: "test2.md", content: "content2", title: "Test 2")

    @adapter.clear

    assert_equal(0, @adapter.size)
    assert_equal(0, @adapter.total_size)
  end

  def test_size_limits
    large_content = "a" * (SwarmMemory::Adapters::Base::MAX_ENTRY_SIZE + 1)

    error = assert_raises(ArgumentError) do
      @adapter.write(file_path: "too_large.md", content: large_content, title: "Too Large")
    end
    assert_match(/exceeds maximum size/, error.message)
  end
end
