# frozen_string_literal: true

module SwarmMemory
  module Adapters
    # Real filesystem adapter using .md/.yml file pairs
    #
    # Architecture:
    # - Content stored in .md files (markdown)
    # - Metadata stored in .yml files (tags, confidence, hits)
    # - Embeddings stored in .emb files (binary, optional)
    # - Paths flattened with -- separator for Git-friendly structure
    # - Stubs for merged/moved entries with auto-redirect
    # - Hit tracking for access patterns
    #
    # Example on disk:
    #   .swarm/memory/
    #   ├── concepts--ruby--classes.md       (content)
    #   ├── concepts--ruby--classes.yml      (metadata)
    #   ├── concepts--ruby--classes.emb      (embedding, optional)
    #   └── _stubs/
    #       ├── old-ruby-intro.md            (stub: "# merged → concepts--ruby--classes")
    #       └── old-ruby-intro.yml           (metadata with stub: true)
    class FilesystemAdapter < Base
      # Stub markers
      STUB_MARKERS = ["# merged →", "# moved →"].freeze

      # Initialize filesystem adapter with directory
      #
      # @param directory [String] Directory path for storage (REQUIRED)
      # @raise [ArgumentError] If directory is not provided
      def initialize(directory:)
        super()
        raise ArgumentError, "directory is required for FilesystemAdapter" if directory.nil? || directory.to_s.strip.empty?

        @directory = File.expand_path(directory)
        @semaphore = Async::Semaphore.new(1) # Fiber-aware concurrency control
        @total_size = 0

        # Create directory if it doesn't exist
        FileUtils.mkdir_p(@directory)

        # Lock file for cross-process synchronization
        @lock_file_path = File.join(@directory, ".lock")

        # Build in-memory index on boot (for fast lookups)
        @index = build_index
      end

      # Write content to filesystem
      #
      # @param file_path [String] Logical path (e.g., "concepts/ruby/classes")
      # @param content [String] Content to store
      # @param title [String] Brief title
      # @param embedding [Array<Float>, nil] Optional embedding vector
      # @param metadata [Hash, nil] Optional metadata
      # @return [Core::Entry] The created entry
      def write(file_path:, content:, title:, embedding: nil, metadata: nil)
        with_write_lock do
          @semaphore.acquire do
            raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?
            raise ArgumentError, "content is required" if content.nil?
            raise ArgumentError, "title is required" if title.nil? || title.to_s.strip.empty?

            # Content is stored as-is (no frontmatter extraction)
            # Metadata comes from tool parameters, not from content
            content_size = content.bytesize

            # Ensure all metadata keys are strings
            stringified_metadata = metadata ? Utils.stringify_keys(metadata) : {}

            # Check entry size limit
            if content_size > MAX_ENTRY_SIZE
              raise ArgumentError, "Content exceeds maximum size (#{format_bytes(MAX_ENTRY_SIZE)}). " \
                "Current: #{format_bytes(content_size)}"
            end

            # Calculate new total size
            existing_size = get_entry_size(file_path)
            new_total_size = @total_size - existing_size + content_size

            # Check total size limit
            if new_total_size > MAX_TOTAL_SIZE
              raise ArgumentError, "Memory storage full (#{format_bytes(MAX_TOTAL_SIZE)} limit). " \
                "Current: #{format_bytes(@total_size)}, " \
                "Would be: #{format_bytes(new_total_size)}. " \
                "Clear old entries or use smaller content."
            end

            # Strip .md extension and flatten path for disk storage
            # "concepts/ruby/classes.md" → "concepts--ruby--classes"
            base_path = file_path.sub(/\.md\z/, "")
            disk_path = flatten_path(base_path)

            # 1. Write content to .md file (stored exactly as provided)
            md_file = File.join(@directory, "#{disk_path}.md")
            FileUtils.mkdir_p(File.dirname(md_file))
            File.write(md_file, content)

            # 2. Write metadata to .yml file
            yaml_file = File.join(@directory, "#{disk_path}.yml")
            existing_hits = read_yaml_field(yaml_file, :hits) || 0

            yaml_data = {
              title: title,
              file_path: file_path, # Logical path with .md extension
              updated_at: Time.now,
              size: content_size,
              hits: existing_hits, # Preserve hit count
              metadata: stringified_metadata, # Metadata from tool parameters
              embedding_checksum: embedding ? checksum(embedding) : nil,
            }
            # Convert symbol keys to strings for clean YAML output
            File.write(yaml_file, YAML.dump(Utils.stringify_keys(yaml_data)))

            # 3. Write embedding to .emb file (binary, optional)
            if embedding
              emb_file = File.join(@directory, "#{disk_path}.emb")
              File.write(emb_file, embedding.pack("f*"))
            end

            # Update total size
            @total_size = new_total_size

            # Update index
            @index[file_path] = {
              disk_path: disk_path,
              title: title,
              size: content_size,
              updated_at: Time.now,
            }

            # Return entry object
            Core::Entry.new(
              content: content,
              title: title,
              updated_at: Time.now,
              size: content_size,
              embedding: embedding,
              metadata: stringified_metadata,
            )
          end
        end
      end

      # Read content from filesystem
      #
      # @param file_path [String] Logical path with .md extension
      # @return [String] Content
      def read(file_path:)
        raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?

        # Strip .md extension and flatten path
        base_path = file_path.sub(/\.md\z/, "")
        disk_path = flatten_path(base_path)
        md_file = File.join(@directory, "#{disk_path}.md")

        raise ArgumentError, "memory://#{file_path} not found" unless File.exist?(md_file)

        content = File.read(md_file)

        # Check if it's a stub (redirect)
        if stub_content?(content)
          target_path = extract_redirect_target(content)
          return read(file_path: target_path) if target_path
        end

        # Increment hit counter
        increment_hits(file_path)

        content
      end

      # Read full entry with all metadata
      #
      # @param file_path [String] Logical path with .md extension
      # @return [Core::Entry] Full entry object
      def read_entry(file_path:)
        raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?

        # Strip .md extension and flatten path
        base_path = file_path.sub(/\.md\z/, "")
        disk_path = flatten_path(base_path)
        md_file = File.join(@directory, "#{disk_path}.md")
        yaml_file = File.join(@directory, "#{disk_path}.yml")

        raise ArgumentError, "memory://#{file_path} not found" unless File.exist?(md_file)

        content = File.read(md_file)

        # Follow stub redirect if applicable
        if stub_content?(content)
          target_path = extract_redirect_target(content)
          return read_entry(file_path: target_path) if target_path
        end

        # Read metadata
        yaml_data = File.exist?(yaml_file) ? YAML.load_file(yaml_file, permitted_classes: [Time, Date, Symbol]) : {}

        # Read embedding if exists
        emb_file = File.join(@directory, "#{disk_path}.emb")
        embedding = if File.exist?(emb_file)
          File.read(emb_file).unpack("f*")
        end

        # Increment hit counter
        increment_hits(file_path)

        Core::Entry.new(
          content: content,
          title: yaml_data["title"] || "Untitled",
          updated_at: parse_time(yaml_data["updated_at"]) || Time.now,
          size: yaml_data["size"] || content.bytesize,
          embedding: embedding,
          metadata: yaml_data["metadata"],
        )
      end

      # Delete entry from filesystem
      #
      # @param file_path [String] Logical path with .md extension
      # @return [void]
      def delete(file_path:)
        with_write_lock do
          @semaphore.acquire do
            raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?

            # Strip .md extension and flatten path
            base_path = file_path.sub(/\.md\z/, "")
            disk_path = flatten_path(base_path)
            md_file = File.join(@directory, "#{disk_path}.md")

            raise ArgumentError, "memory://#{file_path} not found" unless File.exist?(md_file)

            # Get size before deletion
            entry_size = get_entry_size(file_path)

            # Delete all related files
            File.delete(md_file) if File.exist?(md_file)
            File.delete(File.join(@directory, "#{disk_path}.yaml")) if File.exist?(File.join(@directory, "#{disk_path}.yaml"))
            File.delete(File.join(@directory, "#{disk_path}.emb")) if File.exist?(File.join(@directory, "#{disk_path}.emb"))

            # Update total size
            @total_size -= entry_size

            # Update index
            @index.delete(file_path)
          end
        end
      end

      # List all entries
      #
      # @param prefix [String, nil] Filter by prefix
      # @return [Array<Hash>] Entry metadata
      def list(prefix: nil)
        # Find all .md files (excluding stubs)
        md_files = Dir.glob(File.join(@directory, "**/*.md"))
          .reject { |f| stub_file?(f) }

        entries = md_files.map do |md_file|
          disk_path = File.basename(md_file, ".md")
          base_logical_path = unflatten_path(disk_path)
          logical_path = "#{base_logical_path}.md" # Add .md extension

          # Filter by prefix if provided (strip .md for comparison)
          next if prefix && !base_logical_path.start_with?(prefix.sub(/\.md\z/, ""))

          yaml_file = md_file.sub(".md", ".yml")
          yaml_data = File.exist?(yaml_file) ? YAML.load_file(yaml_file, permitted_classes: [Time, Date, Symbol]) : {}

          {
            path: logical_path, # With .md extension
            title: yaml_data["title"] || "Untitled",
            size: yaml_data["size"] || File.size(md_file),
            updated_at: parse_time(yaml_data["updated_at"]) || File.mtime(md_file),
          }
        end.compact

        entries.sort_by { |e| e[:path] }
      end

      # Search by glob pattern
      #
      # @param pattern [String] Glob pattern (e.g., "concepts/**/*.md")
      # @return [Array<Hash>] Matching entries
      def glob(pattern:)
        raise ArgumentError, "pattern is required" if pattern.nil? || pattern.to_s.strip.empty?

        # Strip .md from pattern and flatten for disk matching
        base_pattern = pattern.sub(/\.md\z/, "")
        disk_pattern = flatten_path(base_pattern)

        # Glob for .md files
        md_files = Dir.glob(File.join(@directory, "#{disk_pattern}.md"))
          .reject { |f| stub_file?(f) }

        results = md_files.map do |md_file|
          disk_path = File.basename(md_file, ".md")
          base_logical_path = unflatten_path(disk_path)
          logical_path = "#{base_logical_path}.md" # Add .md extension

          yaml_file = md_file.sub(".md", ".yml")
          yaml_data = File.exist?(yaml_file) ? YAML.load_file(yaml_file, permitted_classes: [Time, Date, Symbol]) : {}

          {
            path: logical_path, # With .md extension
            title: yaml_data["title"] || "Untitled",
            size: File.size(md_file),
            updated_at: parse_time(yaml_data["updated_at"]) || File.mtime(md_file),
          }
        end

        results.sort_by { |e| -e[:updated_at].to_f }
      end

      # Search by content pattern
      #
      # Fast path: grep .yml files first (metadata)
      # Fallback: grep .md files (content)
      #
      # @param pattern [String] Regex pattern
      # @param case_insensitive [Boolean] Case-insensitive search
      # @param output_mode [String] Output mode
      # @return [Array<Hash>] Results
      def grep(pattern:, case_insensitive: false, output_mode: "files_with_matches")
        raise ArgumentError, "pattern is required" if pattern.nil? || pattern.to_s.strip.empty?

        flags = case_insensitive ? Regexp::IGNORECASE : 0
        regex = Regexp.new(pattern, flags)

        case output_mode
        when "files_with_matches"
          grep_files_with_matches(regex)
        when "content"
          grep_with_content(regex)
        when "count"
          grep_with_count(regex)
        else
          raise ArgumentError, "Invalid output_mode: #{output_mode}"
        end
      end

      # Clear all entries
      #
      # @return [void]
      def clear
        with_write_lock do
          @semaphore.acquire do
            # Delete all .md, .yml, .emb files
            Dir.glob(File.join(@directory, "**/*.{md,yml,emb}")).each do |file|
              File.delete(file)
            end

            @total_size = 0
            @index = {}
          end
        end
      end

      # Get current total size
      #
      # @return [Integer] Total size in bytes
      attr_reader :total_size

      # Get number of entries
      #
      # @return [Integer] Number of entries
      def size
        @index.size
      end

      # Get all entries (for optimization/analysis)
      #
      # @return [Hash<String, Core::Entry>] All entries
      def all_entries
        entries = {}

        @index.each do |logical_path, _index_data|
          entries[logical_path] = read_entry(file_path: logical_path)
        rescue ArgumentError
          # Skip entries that can't be read
          next
        end

        entries
      end

      private

      # Flatten path for disk storage
      # "concepts/ruby/classes" → "concepts--ruby--classes"
      #
      # @param logical_path [String] Logical path with slashes
      # @return [String] Flattened path with --
      def flatten_path(logical_path)
        logical_path.gsub("/", "--")
      end

      # Unflatten path from disk storage
      # "concepts--ruby--classes" → "concepts/ruby/classes"
      #
      # @param disk_path [String] Flattened path
      # @return [String] Logical path with slashes
      def unflatten_path(disk_path)
        disk_path.gsub("--", "/")
      end

      # Check if content is a stub (redirect)
      #
      # @param content [String] File content
      # @return [Boolean] True if stub
      def stub_content?(content)
        STUB_MARKERS.any? { |marker| content.start_with?(marker) }
      end

      # Check if file is a stub
      #
      # @param file_path [String] Path to .md file
      # @return [Boolean] True if stub
      def stub_file?(file_path)
        return false unless File.exist?(file_path)

        # Read first 100 bytes to check for stub markers
        content = File.read(file_path, 100)
        stub_content?(content)
      rescue StandardError
        false
      end

      # Extract redirect target from stub content
      #
      # @param content [String] Stub content
      # @return [String, nil] Target path or nil
      def extract_redirect_target(content)
        STUB_MARKERS.each do |marker|
          next unless content.start_with?(marker)

          # Extract path after marker
          match = content.match(/#{Regexp.escape(marker)}\s+(.+?)$/m)
          return match[1].strip if match
        end
        nil
      end

      # Increment hit counter for an entry
      #
      # @param file_path [String] Logical path with .md extension
      # @return [void]
      def increment_hits(file_path)
        base_path = file_path.sub(/\.md\z/, "")
        disk_path = flatten_path(base_path)
        yaml_file = File.join(@directory, "#{disk_path}.yml")
        return unless File.exist?(yaml_file)

        @semaphore.acquire do
          data = YAML.load_file(yaml_file, permitted_classes: [Time, Date, Symbol])
          # Use string key to match the rest of the YAML file
          data["hits"] = (data[:hits] || data["hits"] || 0) + 1
          File.write(yaml_file, YAML.dump(data))
        end
      rescue StandardError => e
        # Don't fail read if hit tracking fails
        warn("Warning: Failed to increment hits for #{file_path}: #{e.message}")
      end

      # Get entry size from .yml or .md file
      #
      # @param file_path [String] Logical path with .md extension
      # @return [Integer] Size in bytes
      def get_entry_size(file_path)
        base_path = file_path.sub(/\.md\z/, "")
        disk_path = flatten_path(base_path)
        yaml_file = File.join(@directory, "#{disk_path}.yml")

        if File.exist?(yaml_file)
          yaml_data = YAML.load_file(yaml_file, permitted_classes: [Time, Date, Symbol])
          yaml_data["size"] || 0
        else
          md_file = File.join(@directory, "#{disk_path}.md")
          File.exist?(md_file) ? File.size(md_file) : 0
        end
      rescue StandardError
        0
      end

      # Read specific field from .yml file
      #
      # @param yaml_file [String] Path to .yml file
      # @param field [Symbol, String] Field to read
      # @return [Object, nil] Field value or nil
      def read_yaml_field(yaml_file, field)
        return unless File.exist?(yaml_file)

        data = YAML.load_file(yaml_file, permitted_classes: [Time, Date, Symbol])
        # YAML files always have string keys (we stringify when writing)
        data[field.to_s]
      rescue StandardError
        nil
      end

      # Build in-memory index of all entries
      #
      # @return [Hash] Index mapping logical_path → metadata
      def build_index
        index = {}
        total = 0

        Dir.glob(File.join(@directory, "**/*.md")).each do |md_file|
          next if stub_file?(md_file)

          disk_path = File.basename(md_file, ".md")
          base_logical_path = unflatten_path(disk_path)
          logical_path = "#{base_logical_path}.md" # Add .md extension

          yaml_file = md_file.sub(".md", ".yml")
          yaml_data = File.exist?(yaml_file) ? YAML.load_file(yaml_file, permitted_classes: [Time, Date, Symbol]) : {}

          size = yaml_data["size"] || File.size(md_file)
          total += size

          index[logical_path] = {
            disk_path: disk_path,
            title: yaml_data["title"] || "Untitled",
            size: size,
            updated_at: parse_time(yaml_data["updated_at"]) || File.mtime(md_file),
          }
        end

        @total_size = total
        index
      end

      # Grep for files with matches (fast path: .yml first)
      #
      # @param regex [Regexp] Pattern to match
      # @return [Array<String>] Matching logical paths with .md extension
      def grep_files_with_matches(regex)
        results = []

        # Fast path: Search .yml files (metadata)
        Dir.glob(File.join(@directory, "**/*.yml")).each do |yaml_file|
          next if yaml_file.include?("_stubs/")

          content = File.read(yaml_file)
          next unless regex.match?(content)

          disk_path = File.basename(yaml_file, ".yml")
          base_path = unflatten_path(disk_path)
          results << "#{base_path}.md" # Add .md extension
        end

        # If found in metadata, return quickly
        return results.sort unless results.empty?

        # Fallback: Search .md files (content)
        Dir.glob(File.join(@directory, "**/*.md")).each do |md_file|
          next if stub_file?(md_file)

          content = File.read(md_file)
          next unless regex.match?(content)

          disk_path = File.basename(md_file, ".md")
          base_path = unflatten_path(disk_path)
          results << "#{base_path}.md" # Add .md extension
        end

        results.uniq.sort
      end

      # Grep with content and line numbers
      #
      # @param regex [Regexp] Pattern to match
      # @return [Array<Hash>] Results with matches
      def grep_with_content(regex)
        results = []

        Dir.glob(File.join(@directory, "**/*.md")).each do |md_file|
          next if stub_file?(md_file)

          content = File.read(md_file)
          matching_lines = []

          content.each_line.with_index(1) do |line, line_num|
            matching_lines << { line_number: line_num, content: line.chomp } if regex.match?(line)
          end

          next if matching_lines.empty?

          disk_path = File.basename(md_file, ".md")
          base_path = unflatten_path(disk_path)
          logical_path = "#{base_path}.md" # Add .md extension

          results << {
            path: logical_path, # With .md extension
            matches: matching_lines,
          }
        end

        results
      end

      # Grep with match counts
      #
      # @param regex [Regexp] Pattern to match
      # @return [Array<Hash>] Results with counts
      def grep_with_count(regex)
        results = []

        Dir.glob(File.join(@directory, "**/*.md")).each do |md_file|
          next if stub_file?(md_file)

          content = File.read(md_file)
          count = content.scan(regex).size

          next if count <= 0

          disk_path = File.basename(md_file, ".md")
          base_path = unflatten_path(disk_path)
          logical_path = "#{base_path}.md" # Add .md extension

          results << {
            path: logical_path, # With .md extension
            count: count,
          }
        end

        results
      end

      # Calculate checksum for embedding
      #
      # @param embedding [Array<Float>] Embedding vector
      # @return [String] Hex checksum
      def checksum(embedding)
        Digest::MD5.hexdigest(embedding.pack("f*"))
      end

      # Parse time from various formats
      #
      # @param value [String, Time, nil] Time value
      # @return [Time, nil] Parsed time
      def parse_time(value)
        return if value.nil?
        return value if value.is_a?(Time)

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      # Execute block with cross-process write lock
      #
      # Uses flock to ensure exclusive access across processes.
      # This prevents corruption when agent writes while defrag runs.
      #
      # @yield Block to execute with lock held
      # @return [Object] Result of block
      def with_write_lock
        # Open lock file (create if doesn't exist)
        File.open(@lock_file_path, File::RDWR | File::CREAT, 0o644) do |lock_file|
          # Acquire exclusive lock (blocks if another process has it)
          lock_file.flock(File::LOCK_EX)

          begin
            # Execute the block with lock held
            yield
          ensure
            # Release lock
            lock_file.flock(File::LOCK_UN)
          end
        end
      end
    end
  end
end
