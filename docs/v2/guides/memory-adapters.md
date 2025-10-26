# Memory Adapter Development Guide

Learn how to build custom storage adapters for SwarmMemory using the plugin architecture.

---

## Overview

SwarmMemory uses a **plugin adapter pattern** for storage, allowing you to implement custom backends that fit your infrastructure:

- **FilesystemAdapter** (built-in) - Stores in `.md/.yml/.emb` files, Git-friendly
- **Custom Adapters** (via registry) - PostgreSQL, MySQL, MongoDB, Qdrant, or any storage you need

**Plugin Architecture Benefits:**
- ✅ SwarmMemory stays lightweight (no forced dependencies)
- ✅ Use your existing ORM (ActiveRecord, Sequel, etc.)
- ✅ Optimize for your infrastructure
- ✅ Community can publish adapters as gems

**Any adapter** that implements the `Adapters::Base` interface will work seamlessly with:
- All memory tools (MemoryWrite, MemoryRead, etc.)
- Semantic search
- Defrag operations
- CLI commands

---

## Adapter Registry

SwarmMemory provides a registry system for custom adapters:

```ruby
# Register your adapter when your app boots
SwarmMemory.register_adapter(:my_adapter, MyCustomAdapter)

# Now use it in configuration
agent :researcher do
  memory do
    adapter :my_adapter
    option :custom_option, "value"
  end
end

# Check available adapters
SwarmMemory.available_adapters
# => [:filesystem, :my_adapter]
```

---

## Adapter Interface

### Required Methods

All adapters MUST inherit from `SwarmMemory::Adapters::Base` and implement these methods:

```ruby
module SwarmMemory
  module Adapters
    class MyAdapter < Base
      # Write an entry
      #
      # @param file_path [String] Logical path (e.g., "concept/ruby/classes.md")
      # @param content [String] Markdown content
      # @param title [String] Entry title
      # @param embedding [Array<Float>, nil] Optional 384-dim embedding vector
      # @param metadata [Hash, nil] Metadata (type, tags, confidence, etc.)
      # @return [Core::Entry] The created entry
      def write(file_path:, content:, title:, embedding: nil, metadata: nil)
        # Implement storage logic
      end

      # Read entry content only
      #
      # @param file_path [String] Logical path
      # @return [String] Content
      # @raise [ArgumentError] If not found
      def read(file_path:)
        # Implement retrieval logic
      end

      # Read full entry with metadata
      #
      # @param file_path [String] Logical path
      # @return [Core::Entry] Full entry object
      # @raise [ArgumentError] If not found
      def read_entry(file_path:)
        # Implement full retrieval logic
      end

      # Delete an entry
      #
      # @param file_path [String] Logical path
      # @return [void]
      # @raise [ArgumentError] If not found
      def delete(file_path:)
        # Implement deletion logic
      end

      # List all entries
      #
      # @param prefix [String, nil] Optional prefix filter
      # @return [Array<Hash>] Array of {path:, title:, size:, updated_at:}
      def list(prefix: nil)
        # Implement listing logic
      end

      # Search by glob pattern
      #
      # @param pattern [String] Glob pattern (e.g., "skill/**/*.md")
      # @return [Array<Hash>] Matching entries
      def glob(pattern:)
        # Implement glob search
      end

      # Search by content regex
      #
      # @param pattern [String] Regex pattern
      # @param case_insensitive [Boolean] Case-insensitive flag
      # @param output_mode [String] "files_with_matches", "content", or "count"
      # @return [Array] Results in requested format
      def grep(pattern:, case_insensitive: false, output_mode: "files_with_matches")
        # Implement grep search
      end

      # Clear all entries
      #
      # @return [void]
      def clear
        # Implement clear logic
      end

      # Get total storage size in bytes
      #
      # @return [Integer] Total size
      def total_size
        # Implement size calculation
      end

      # Get number of entries
      #
      # @return [Integer] Entry count
      def size
        # Implement count
      end

      # Get all entries (for defrag operations)
      #
      # @return [Hash<String, Core::Entry>] All entries keyed by path
      def all_entries
        # Implement bulk retrieval
      end

      # Semantic search by embedding vector (REQUIRED for semantic search)
      #
      # @param embedding [Array<Float>] Query embedding (384-dim)
      # @param top_k [Integer] Number of results
      # @param threshold [Float] Minimum similarity (0.0-1.0)
      # @return [Array<Hash>] Results with :path, :similarity, :title, :metadata
      def semantic_search(embedding:, top_k: 10, threshold: 0.0)
        # Implement semantic search
      end
    end
  end
end
```

---

## Configuration DSL

The memory configuration DSL supports passing options to custom adapters:

```ruby
# Filesystem adapter (built-in)
agent :researcher do
  memory do
    adapter :filesystem
    directory ".swarm/memory/researcher"
  end
end

# Custom adapter with options
agent :researcher do
  memory do
    adapter :activerecord
    option :namespace, "researcher"
    option :table_name, "memory_entries"
  end
end

# Options are passed to adapter's initialize method
# MyAdapter.new(namespace: "researcher", table_name: "memory_entries")
```

---

## Example: ActiveRecord Adapter (PostgreSQL/Rails)

Complete example using Rails with ActiveRecord and PostgreSQL:

### Step 1: Migration

```ruby
# db/migrate/20250126_create_memory_entries.rb
class CreateMemoryEntries < ActiveRecord::Migration[7.1]
  def change
    # Enable pgvector extension for embeddings
    enable_extension 'vector'

    create_table :memory_entries, id: false do |t|
      t.string :namespace, null: false
      t.string :path, null: false
      t.text :content, null: false
      t.string :title, null: false
      t.column :embedding, :vector, limit: 384
      t.jsonb :metadata, default: {}
      t.integer :size, null: false
      t.integer :hits, default: 0
      t.timestamps
    end

    # Primary key on namespace + path
    add_index :memory_entries, [:namespace, :path], unique: true

    # Indexes for performance
    add_index :memory_entries, :namespace
    add_index :memory_entries, :metadata, using: :gin
    add_index :memory_entries, :embedding, using: :hnsw, opclass: :vector_cosine_ops

    # Full-text search index
    execute <<-SQL
      CREATE INDEX index_memory_entries_content_tsvector
      ON memory_entries
      USING GIN(to_tsvector('english', content))
    SQL
  end
end
```

### Step 2: Model

```ruby
# app/models/memory_entry.rb
class MemoryEntry < ApplicationRecord
  validates :path, :namespace, :content, :title, presence: true
  validates :path, uniqueness: { scope: :namespace }

  scope :in_namespace, ->(ns) { where(namespace: ns) }

  scope :matching_content, ->(pattern, case_insensitive) {
    operator = case_insensitive ? "~*" : "~"
    where("content #{operator} ?", pattern)
  }

  def self.similar_to(embedding, threshold: 0.0, limit: 10)
    where("embedding IS NOT NULL")
      .where("1 - (embedding <=> ?) >= ?", embedding.to_s, threshold)
      .order(Arel.sql("embedding <=> '#{embedding}'"))
      .limit(limit)
  end

  def increment_hits!
    increment!(:hits)
  end
end
```

### Step 3: Adapter Implementation

See the complete ActiveRecord adapter implementation in the separate documentation file:
**[docs/v2/swarm_memory_adapters.md](../swarm_memory_adapters.md)**

The adapter includes:
- Full CRUD operations using ActiveRecord
- PostgreSQL full-text search for fast grep
- pgvector integration for semantic search
- Proper error handling and validation
- ~300 lines of production-ready code

###Step 4: Register the Adapter

```ruby
# config/initializers/swarm_memory.rb
require_relative '../../lib/activerecord_memory_adapter'

SwarmMemory.register_adapter(:activerecord, ActiveRecordMemoryAdapter)
```

### Step 5: Configure Your Agent

```ruby
# swarm.rb
agent :researcher do
  memory do
    adapter :activerecord
    option :namespace, "researcher"
  end
end
```

---

## Legacy Example: Qdrant Adapter

> **Note**: This is a conceptual example. For production use with vector databases,
> implement and register your own adapter using the pattern above.

```ruby
# Conceptual example - not maintained
class QdrantAdapter < SwarmMemory::Adapters::Base
      def initialize(url:, collection:, api_key: nil)
        super()
        @client = Qdrant::Client.new(url: url, api_key: api_key)
        @collection = collection
        @total_size = 0

        # Ensure collection exists
        ensure_collection_exists
      end

      def write(file_path:, content:, title:, embedding: nil, metadata: nil)
        # Calculate size
        content_size = content.bytesize

        # Store in Qdrant
        @client.upsert(
          collection_name: @collection,
          points: [{
            id: file_path,  # Use path as ID
            vector: embedding || [],
            payload: {
              content: content,
              title: title,
              size: content_size,
              updated_at: Time.now.to_i,
              metadata: metadata || {}
            }
          }]
        )

        @total_size += content_size

        # Return entry
        Core::Entry.new(
          content: content,
          title: title,
          updated_at: Time.now,
          size: content_size,
          embedding: embedding,
          metadata: metadata
        )
      end

      def read(file_path:)
        result = @client.retrieve(
          collection_name: @collection,
          ids: [file_path]
        )

        raise ArgumentError, "memory://#{file_path} not found" if result.empty?

        result.first.payload["content"]
      end

      def read_entry(file_path:)
        result = @client.retrieve(
          collection_name: @collection,
          ids: [file_path]
        )

        raise ArgumentError, "memory://#{file_path} not found" if result.empty?

        point = result.first
        payload = point.payload

        Core::Entry.new(
          content: payload["content"],
          title: payload["title"],
          updated_at: Time.at(payload["updated_at"]),
          size: payload["size"],
          embedding: point.vector,
          metadata: payload["metadata"]
        )
      end

      def delete(file_path:)
        result = @client.delete(
          collection_name: @collection,
          points: [file_path]
        )

        raise ArgumentError, "memory://#{file_path} not found" unless result.ok?

        entry = read_entry(file_path: file_path)
        @total_size -= entry.size
      end

      def list(prefix: nil)
        # Scroll through all points
        results = @client.scroll(
          collection_name: @collection,
          limit: 1000
        )

        entries = results.points.map do |point|
          {
            path: point.id,
            title: point.payload["title"],
            size: point.payload["size"],
            updated_at: Time.at(point.payload["updated_at"])
          }
        end

        # Filter by prefix if provided
        if prefix
          entries.select { |e| e[:path].start_with?(prefix) }
        else
          entries
        end
      end

      def glob(pattern:)
        # Convert glob to regex
        regex = glob_to_regex(pattern)

        list.select { |entry| regex.match?(entry[:path]) }
      end

      def grep(pattern:, case_insensitive: false, output_mode: "files_with_matches")
        flags = case_insensitive ? Regexp::IGNORECASE : 0
        regex = Regexp.new(pattern, flags)

        all_entries = all_entries()

        case output_mode
        when "files_with_matches"
          all_entries.keys.select { |path| regex.match?(all_entries[path].content) }
        when "content"
          # Return matching lines with line numbers
          all_entries.map do |path, entry|
            matches = entry.content.lines.each_with_index.select { |line, _| regex.match?(line) }
            next if matches.empty?

            {
              path: path,
              matches: matches.map { |line, idx| { line_number: idx + 1, content: line.chomp } }
            }
          end.compact
        when "count"
          all_entries.map do |path, entry|
            count = entry.content.scan(regex).size
            next if count <= 0

            { path: path, count: count }
          end.compact
        end
      end

      def clear
        @client.delete_collection(collection_name: @collection)
        ensure_collection_exists
        @total_size = 0
      end

      def total_size
        @total_size
      end

      def size
        list.size
      end

      def all_entries
        results = @client.scroll(
          collection_name: @collection,
          limit: 10000
        )

        results.points.each_with_object({}) do |point, hash|
          hash[point.id] = Core::Entry.new(
            content: point.payload["content"],
            title: point.payload["title"],
            updated_at: Time.at(point.payload["updated_at"]),
            size: point.payload["size"],
            embedding: point.vector,
            metadata: point.payload["metadata"]
          )
        end
      end

      # Semantic search (Qdrant's strength!)
      def semantic_search(embedding:, top_k: 10, threshold: 0.0)
        result = @client.search(
          collection_name: @collection,
          vector: embedding,
          limit: top_k,
          score_threshold: threshold
        )

        result.map do |hit|
          {
            path: hit.id,
            similarity: hit.score,
            title: hit.payload["title"],
            size: hit.payload["size"],
            updated_at: Time.at(hit.payload["updated_at"]),
            metadata: hit.payload["metadata"]
          }
        end
      end

      private

      def ensure_collection_exists
        @client.create_collection(
          collection_name: @collection,
          vectors: {
            size: 384,  # all-MiniLM-L6-v2 dimensions
            distance: "Cosine"
          }
        )
      rescue Qdrant::Errors::ApiError => e
        # Collection already exists
        raise unless e.message.include?("already exists")
      end

      def glob_to_regex(pattern)
        # Convert glob wildcards to regex
        regex_pattern = pattern
          .gsub("**", "DOUBLE_STAR")
          .gsub("*", "[^/]*")
          .gsub("DOUBLE_STAR", ".*")
          .gsub("?", ".")

        Regexp.new("^#{regex_pattern}$")
      end
    end
  end
end
```

---

## Adapter Comparison

| Feature | FilesystemAdapter (built-in) | ActiveRecord (example) | Vector DB (custom) |
|---------|------------------------------|------------------------|-------------------|
| **Storage** | Local files | PostgreSQL/MySQL | Qdrant/Milvus/Weaviate |
| **Semantic Search** | In-memory cosine | pgvector extension | Native vector search |
| **Scalability** | ~5K entries | Hundreds of thousands | Millions of entries |
| **Setup** | Zero config | Rails + migration | External service |
| **Dependencies** | None | activerecord, pg/mysql2 | qdrant-ruby, etc. |
| **Performance** | Good (<5K entries) | Good (with indexes) | Excellent (any size) |
| **Cost** | Free | Managed DB (~$10/mo) | Self-hosted or cloud |
| **Availability** | Built-in | You implement | You implement |

> **Note**: Only FilesystemAdapter is built-in. All other adapters are examples you implement and register using `SwarmMemory.register_adapter`.

---

## Testing Adapters

### Unit Tests

```ruby
class MyAdapterTest < Minitest::Test
  def setup
    @adapter = MyAdapter.new(...)
  end

  def test_write_and_read
    entry = @adapter.write(
      file_path: "test/entry.md",
      content: "Test content",
      title: "Test",
      metadata: { "type" => "concept" }
    )

    assert_equal "Test content", @adapter.read(file_path: "test/entry.md")
  end

  def test_semantic_search
    # Write entries with embeddings
    @adapter.write(
      file_path: "test/entry1.md",
      content: "Ruby classes",
      title: "Classes",
      embedding: [0.1, 0.2, ...],  # 384-dim vector
      metadata: { "type" => "concept" }
    )

    # Search
    query_embedding = [0.1, 0.2, ...]  # Similar vector
    results = @adapter.semantic_search(
      embedding: query_embedding,
      top_k: 5,
      threshold: 0.5
    )

    assert_equal 1, results.size
    assert_equal "test/entry1.md", results.first[:path]
    assert results.first[:similarity] > 0.5
  end

  def test_glob_search
    @adapter.write(file_path: "concept/ruby/classes.md", ...)
    @adapter.write(file_path: "concept/ruby/modules.md", ...)

    results = @adapter.glob(pattern: "concept/ruby/*")

    assert_equal 2, results.size
  end
end
```

### Integration Tests

```ruby
def test_adapter_works_with_storage
  adapter = MyAdapter.new(...)
  embedder = SwarmMemory::Embeddings::InformersEmbedder.new
  storage = SwarmMemory::Core::Storage.new(adapter: adapter, embedder: embedder)

  # Test via Storage API
  storage.write(
    file_path: "test/entry.md",
    content: "Test",
    title: "Test"
  )

  content = storage.read(file_path: "test/entry.md")
  assert_equal "Test", content
end

def test_adapter_works_with_memory_tools
  adapter = MyAdapter.new(...)
  storage = SwarmMemory::Core::Storage.new(adapter: adapter)

  tool = SwarmMemory::Tools::MemoryWrite.new(storage: storage, agent_name: :test)

  result = tool.execute(
    file_path: "test/entry.md",
    content: "Content",
    title: "Title",
    type: "concept",
    # ... all required params
  )

  assert_match /Stored at memory/, result
end
```

---

## FilesystemAdapter Deep Dive

Study the reference implementation:

### File Structure

```
.swarm/memory/
├── concept--ruby--classes.md       # Markdown content
├── concept--ruby--classes.yml      # Metadata (YAML)
├── concept--ruby--classes.emb      # Embedding (binary)
└── .lock                           # File lock
```

**Path Flattening:**
- Logical: `concept/ruby/classes.md`
- Disk: `concept--ruby--classes.md`
- Why: Git-friendly, avoids nested directories

### Key Implementation Details

```ruby
class FilesystemAdapter < Base
  def initialize(directory:)
    @directory = File.expand_path(directory)
    @semaphore = Async::Semaphore.new(1)  # Fiber-safe locking
    @lock_file_path = File.join(@directory, ".lock")
    @index = build_index  # In-memory index for fast lookups
  end

  def write(file_path:, content:, title:, embedding: nil, metadata: nil)
    with_write_lock do
      @semaphore.acquire do
        # Flatten path for disk storage
        disk_path = flatten_path(file_path)

        # Write content (.md file)
        File.write(File.join(@directory, "#{disk_path}.md"), content)

        # Write metadata (.yml file)
        yaml_data = {
          title: title,
          file_path: file_path,
          updated_at: Time.now,
          size: content.bytesize,
          metadata: metadata,
          embedding_checksum: embedding ? checksum(embedding) : nil
        }
        File.write(File.join(@directory, "#{disk_path}.yml"), YAML.dump(yaml_data))

        # Write embedding (.emb file, binary)
        if embedding
          File.write(File.join(@directory, "#{disk_path}.emb"), embedding.pack("f*"))
        end

        # Update in-memory index
        @index[file_path] = {...}
      end
    end
  end

  # Cross-process file locking
  def with_write_lock
    File.open(@lock_file_path, File::RDWR | File::CREAT) do |lock_file|
      lock_file.flock(File::LOCK_EX)  # Exclusive lock
      yield
    ensure
      lock_file.flock(File::LOCK_UN)  # Release
    end
  end
end
```

**Optimizations:**
- In-memory index for fast lookups
- File locking for concurrent access
- Binary embeddings (not JSON)
- Lazy loading (index built on init)

---

## Vector Database Adapters

### Qdrant Example (Production-Ready)

See full example above in "Example: QdrantAdapter" section.

**Benefits:**
- Native vector search (faster, more scalable)
- Built-in similarity algorithms
- Filtering by metadata
- Horizontal scaling

**Trade-offs:**
- Requires external service
- More complex setup
- Additional dependency

### Milvus Adapter

```ruby
class MilvusAdapter < Base
  def initialize(host:, port:, collection:)
    @client = Milvus::Client.new(host: host, port: port)
    @collection = collection
  end

  def semantic_search(embedding:, top_k:, threshold:)
    @client.search(
      collection_name: @collection,
      vectors: [embedding],
      top_k: top_k,
      params: { nprobe: 10 }
    ).map do |result|
      {
        path: result.id,
        similarity: result.distance,
        # ... map other fields
      }
    end
  end
end
```

---

## Relational Database Adapters

### PostgreSQL with pgvector

```ruby
class PostgresAdapter < Base
  def initialize(connection_string:)
    @conn = PG.connect(connection_string)

    # Ensure pgvector extension and table exist
    @conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
    @conn.exec(<<~SQL)
      CREATE TABLE IF NOT EXISTS memories (
        file_path TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        title TEXT NOT NULL,
        embedding vector(384),
        metadata JSONB,
        updated_at TIMESTAMP DEFAULT NOW()
      )
    SQL

    # Create index for vector similarity search
    @conn.exec("CREATE INDEX IF NOT EXISTS memories_embedding_idx ON memories USING ivfflat (embedding vector_cosine_ops)")
  end

  def write(file_path:, content:, title:, embedding: nil, metadata: nil)
    @conn.exec_params(
      "INSERT INTO memories (file_path, content, title, embedding, metadata, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (file_path) DO UPDATE
       SET content = $2, title = $3, embedding = $4, metadata = $5, updated_at = $6",
      [file_path, content, title, embedding&.to_s, metadata.to_json, Time.now]
    )

    # Return entry
    Core::Entry.new(...)
  end

  def semantic_search(embedding:, top_k:, threshold:)
    # pgvector cosine similarity
    result = @conn.exec_params(
      "SELECT file_path, title, metadata,
              1 - (embedding <=> $1::vector) AS similarity
       FROM memories
       WHERE (1 - (embedding <=> $1::vector)) >= $2
       ORDER BY embedding <=> $1::vector
       LIMIT $3",
      [embedding.to_s, threshold, top_k]
    )

    result.map do |row|
      {
        path: row["file_path"],
        similarity: row["similarity"].to_f,
        title: row["title"],
        metadata: JSON.parse(row["metadata"])
      }
    end
  end

  def glob(pattern:)
    # Convert glob to SQL LIKE pattern
    like_pattern = pattern.gsub("**", "%").gsub("*", "%").gsub("?", "_")

    result = @conn.exec_params(
      "SELECT file_path, title, LENGTH(content) as size, updated_at
       FROM memories
       WHERE file_path LIKE $1",
      [like_pattern]
    )

    result.map do |row|
      {
        path: row["file_path"],
        title: row["title"],
        size: row["size"].to_i,
        updated_at: Time.parse(row["updated_at"])
      }
    end
  end
end
```

---

## Adapter Checklist

When building an adapter, ensure:

### Functional Requirements

- [ ] All 14 required methods implemented
- [ ] Raises `ArgumentError` when entry not found
- [ ] Returns `Core::Entry` objects from read_entry
- [ ] Handles nil embeddings gracefully
- [ ] Handles nil metadata gracefully
- [ ] Supports prefix filtering in list()
- [ ] Glob patterns work correctly
- [ ] Grep supports all 3 output modes
- [ ] semantic_search returns sorted by similarity (descending)

### Performance Requirements

- [ ] Lookups use indexes (not full scans)
- [ ] Writes are atomic (no partial updates)
- [ ] Concurrent access handled safely
- [ ] Embeddings stored efficiently (binary, not JSON)
- [ ] list() is paginated or limited (for large datasets)

### Quality Requirements

- [ ] Thread-safe (or document as single-threaded only)
- [ ] Fiber-safe (if using Async)
- [ ] Errors have helpful messages
- [ ] Cleanup on adapter destruction
- [ ] Configuration validated on init
- [ ] Total size tracking (if possible)

---

## Using Custom Adapters

### Step 1: Implement Your Adapter

```ruby
# lib/my_custom_adapter.rb
class MyCustomAdapter < SwarmMemory::Adapters::Base
  def initialize(url:, api_key: nil, **options)
    super()
    # Your initialization code
  end

  # Implement all required methods...
  # See Adapters::Base for full interface
end
```

### Step 2: Register Your Adapter

```ruby
# config/initializers/swarm_memory.rb (Rails)
# or at the top of your swarm.rb file

require_relative 'lib/my_custom_adapter'

SwarmMemory.register_adapter(:my_adapter, MyCustomAdapter)
```

### Step 3: Configure Agent to Use It

```ruby
# swarm.rb
agent :assistant do
  memory do
    adapter :my_adapter  # Uses registered adapter
    option :url, "http://localhost:8080"
    option :api_key, ENV["API_KEY"]
  end
end
```

### With Storage Directly (Without SwarmSDK)

```ruby
require 'swarm_memory'

# Create your adapter
adapter = MyCustomAdapter.new(url: "http://localhost:6333")

# Create storage with embedder
embedder = SwarmMemory::Embeddings::InformersEmbedder.new
storage = SwarmMemory::Core::Storage.new(adapter: adapter, embedder: embedder)

# Use memory tools directly
tools = SwarmMemory.tools_for(storage: storage, agent_name: :test)
```

---

## Publishing Your Adapter

Consider publishing your adapter as a gem for community use:

```ruby
# my_adapter_gem.gemspec
Gem::Specification.new do |spec|
  spec.name = "swarm_memory_my_adapter"
  spec.version = "1.0.0"
  spec.summary = "MyAdapter for SwarmMemory"

  spec.add_dependency "swarm_memory", "~> 1.0"
  spec.add_dependency "my_database_client", "~> 2.0"
end
```

Users can then:
```bash
gem install swarm_memory_my_adapter
```

```ruby
# In their app
require 'swarm_memory_my_adapter'
SwarmMemory.register_adapter(:my_adapter, MyCustomAdapter)
```

---

## See Also

- **Complete ActiveRecord Example:** [docs/v2/swarm_memory_adapters.md](../swarm_memory_adapters.md)
- **Base Class:** `lib/swarm_memory/adapters/base.rb` - Interface definition
- **Reference Implementation:** `lib/swarm_memory/adapters/filesystem_adapter.rb`
- **Entry Class:** `lib/swarm_memory/core/entry.rb` - Entry object spec
- **Storage Class:** `lib/swarm_memory/core/storage.rb` - Storage orchestration
- **Registry API:** `lib/swarm_memory.rb` - register_adapter, adapter_for, available_adapters
