# frozen_string_literal: true

require "test_helper"

module SwarmMemory
  module Core
    # Tests for Storage redirect functionality (stub following)
    #
    # This test suite verifies that Storage#read_entry correctly handles
    # stub redirects created by MemoryDefrag, including:
    # - Single redirects
    # - Redirect chains
    # - Circular redirect detection
    # - Depth limit enforcement
    # - Error handling for malformed stubs
    class StorageRedirectTest < Minitest::Test
      def setup
        @temp_dir = Dir.mktmpdir
        adapter = Adapters::FilesystemAdapter.new(directory: @temp_dir)
        @storage = Storage.new(adapter: adapter)
      end

      def teardown
        FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
      end

      # Test: read_entry follows single redirect
      def test_read_entry_follows_single_redirect
        # Create final entry
        @storage.write(
          file_path: "concept/ruby/classes.md",
          content: "# Ruby Classes\n\nClasses are blueprints...",
          title: "Ruby Classes",
        )

        # Create stub: old-classes → classes
        @storage.adapter.write(
          file_path: "concept/ruby/old-classes.md",
          content: "# merged → concept/ruby/classes.md\n\nThis entry was merged into concept/ruby/classes.md.",
          title: "[STUB] → concept/ruby/classes.md",
          metadata: { "stub" => true, "redirect_to" => "concept/ruby/classes.md", "reason" => "merged" },
        )

        # Reading old path should return new entry
        entry = @storage.read_entry(file_path: "concept/ruby/old-classes.md")

        assert_equal("# Ruby Classes\n\nClasses are blueprints...", entry.content)
        assert_equal("Ruby Classes", entry.title)
      end

      # Test: read_entry follows chain of redirects
      def test_read_entry_follows_redirect_chain
        # Create final entry
        @storage.write(
          file_path: "concept/final.md",
          content: "Final content",
          title: "Final",
        )

        # Create chain: a → b → c → final
        @storage.adapter.write(
          file_path: "concept/c.md",
          content: "# moved → concept/final.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/final.md", "reason" => "moved" },
        )

        @storage.adapter.write(
          file_path: "concept/b.md",
          content: "# moved → concept/c.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/c.md", "reason" => "moved" },
        )

        @storage.adapter.write(
          file_path: "concept/a.md",
          content: "# moved → concept/b.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/b.md", "reason" => "moved" },
        )

        # Reading 'a' should return 'final'
        entry = @storage.read_entry(file_path: "concept/a.md")

        assert_equal("Final content", entry.content)
        assert_equal("Final", entry.title)
      end

      # Test: read_entry detects circular redirects
      def test_read_entry_detects_circular_redirect
        # Create circular redirect: a → b → a
        @storage.adapter.write(
          file_path: "concept/a.md",
          content: "# merged → concept/b.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/b.md", "reason" => "merged" },
        )

        @storage.adapter.write(
          file_path: "concept/b.md",
          content: "# merged → concept/a.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/a.md", "reason" => "merged" },
        )

        # Should detect cycle immediately
        error = assert_raises(ArgumentError) do
          @storage.read_entry(file_path: "concept/a.md")
        end

        assert_match(/Circular redirect detected/, error.message)
        assert_match(%r{concept/a\.md → concept/b\.md → concept/a\.md}, error.message)
        assert_match(/MemoryDefrag/, error.message)
      end

      # Test: read_entry enforces depth limit
      def test_read_entry_enforces_depth_limit
        # Create chain with 6 redirects (exceeds limit of 5)
        @storage.write(file_path: "concept/g.md", content: "Final", title: "G")

        @storage.adapter.write(
          file_path: "concept/f.md",
          content: "# moved → concept/g.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/g.md", "reason" => "moved" },
        )

        @storage.adapter.write(
          file_path: "concept/e.md",
          content: "# moved → concept/f.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/f.md", "reason" => "moved" },
        )

        @storage.adapter.write(
          file_path: "concept/d.md",
          content: "# moved → concept/e.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/e.md", "reason" => "moved" },
        )

        @storage.adapter.write(
          file_path: "concept/c.md",
          content: "# moved → concept/d.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/d.md", "reason" => "moved" },
        )

        @storage.adapter.write(
          file_path: "concept/b.md",
          content: "# moved → concept/c.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/c.md", "reason" => "moved" },
        )

        @storage.adapter.write(
          file_path: "concept/a.md",
          content: "# moved → concept/b.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/b.md", "reason" => "moved" },
        )

        # Should fail with depth limit error
        error = assert_raises(ArgumentError) do
          @storage.read_entry(file_path: "concept/a.md")
        end

        assert_match(/too deep \(>5 redirects\)/, error.message)
        assert_match(/MemoryDefrag/, error.message)
        assert_match(/dry_run/, error.message)
      end

      # Test: read_entry fails on missing redirect target
      def test_read_entry_fails_on_missing_redirect_target
        # Create stub pointing to non-existent entry
        @storage.adapter.write(
          file_path: "concept/a.md",
          content: "# merged → concept/nonexistent.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/nonexistent.md", "reason" => "merged" },
        )

        # Should provide helpful error
        error = assert_raises(ArgumentError) do
          @storage.read_entry(file_path: "concept/a.md")
        end

        assert_match(/was redirected to.*nonexistent\.md, but the target was not found/, error.message)
        assert_match(/MemoryDefrag/, error.message)
        assert_match(/analyze/, error.message)
      end

      # Test: read_entry fails on malformed stub metadata
      def test_read_entry_fails_on_malformed_stub_metadata
        # Create stub with invalid metadata (missing redirect_to)
        @storage.adapter.write(
          file_path: "concept/a.md",
          content: "# merged → somewhere",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => nil }, # Invalid!
        )

        error = assert_raises(ArgumentError) do
          @storage.read_entry(file_path: "concept/a.md")
        end

        assert_match(/invalid redirect metadata/, error.message)
        assert_match(/should never happen/, error.message)
        assert_match(/corrupted/, error.message)
      end

      # Test: read_entry fails on empty redirect_to
      def test_read_entry_fails_on_empty_redirect_to
        # Create stub with empty redirect_to
        @storage.adapter.write(
          file_path: "concept/a.md",
          content: "# merged",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "", "reason" => "merged" },
        )

        error = assert_raises(ArgumentError) do
          @storage.read_entry(file_path: "concept/a.md")
        end

        assert_match(/invalid redirect metadata/, error.message)
      end

      # Test: read() delegates to read_entry and returns content
      def test_read_delegates_to_read_entry
        @storage.write(
          file_path: "concept/test.md",
          content: "Test content",
          title: "Test",
        )

        content = @storage.read(file_path: "concept/test.md")

        assert_equal("Test content", content)
      end

      # Test: read() follows redirects (via read_entry)
      def test_read_follows_redirects
        # Create final entry
        @storage.write(
          file_path: "concept/final.md",
          content: "Final content",
          title: "Final",
        )

        # Create stub
        @storage.adapter.write(
          file_path: "concept/old.md",
          content: "# merged → concept/final.md",
          title: "[STUB]",
          metadata: { "stub" => true, "redirect_to" => "concept/final.md", "reason" => "merged" },
        )

        # Reading stub should return final content
        content = @storage.read(file_path: "concept/old.md")

        assert_equal("Final content", content)
      end

      # Test: Non-stub entries are returned as-is
      def test_read_entry_returns_non_stub_entries_as_is
        @storage.write(
          file_path: "concept/normal.md",
          content: "Normal content",
          title: "Normal",
        )

        entry = @storage.read_entry(file_path: "concept/normal.md")

        assert_equal("Normal content", entry.content)
        assert_equal("Normal", entry.title)
        # Should not have stub metadata
        refute(entry.metadata&.dig("stub"))
      end
    end
  end
end
