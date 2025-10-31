# MemoryDefrag Tool - Complete Guide

**Comprehensive documentation for implementing MemoryDefrag support in custom storage adapters.**

---

## Table of Contents

1. [What is MemoryDefrag?](#1-what-is-memorydefrag)
2. [Interface Requirements](#2-interface-requirements)
3. [How MemoryDefrag Works](#3-how-memorydefrag-works)
4. [Usage Patterns](#4-usage-patterns)
5. [Adapter Compatibility](#5-adapter-compatibility)
6. [PostgreSQL Implementation](#6-postgresql-implementation)

---

## 1. What is MemoryDefrag?

### Overview

**MemoryDefrag** is a comprehensive memory optimization tool that analyzes and maintains the quality of agent memory storage. It's like a **defragmentation and optimization utility** for AI memory.

### Purpose

MemoryDefrag solves several critical problems:

1. **Duplicate Detection**: Finds similar/duplicate entries that waste space
2. **Quality Assessment**: Identifies entries with poor metadata
3. **Archival Management**: Finds old, unused entries that could be deleted
4. **Knowledge Graph Building**: Discovers and creates relationships between entries
5. **Storage Optimization**: Merges duplicates, cleans up stubs, compacts low-value entries

### When to Use

- **Every 15-20 new entries**: Light analysis
- **Every 50 entries**: Medium check (analyze + find issues)
- **Every 100 entries**: Heavy maintenance (full optimization)
- **When searches return irrelevant results**: Quality degradation
- **Before major tasks**: Check memory health

---

## 2. Interface Requirements

### Required Adapter Methods

MemoryDefrag uses the **standard adapter interface**. No special methods required!

#### Core Methods Used

```ruby
# 1. LIST - Get all entries
@adapter.list(prefix: nil)
# Returns: Array<Hash> with { path:, title:, size:, updated_at: }

# 2. READ_ENTRY - Get full entry with metadata
@adapter.read_entry(file_path: "concept/ruby/classes.md")
# Returns: Core::Entry with content, title, metadata, embedding, size, updated_at

# 3. WRITE - Update entries (for merging, linking)
@adapter.write(
  file_path: "concept/ruby/classes.md",
  content: "...",
  title: "...",
  embedding: [...],
  metadata: { "type" => "concept", "related" => [...], ... }
)
# Returns: Core::Entry

# 4. DELETE - Remove entries (for cleanup, compact)
@adapter.delete(file_path: "concept/ruby/classes.md")
# Returns: void

# 5. TOTAL_SIZE - Get storage size
@adapter.total_size
# Returns: Integer (bytes)

# 6. ALL_ENTRIES - Get all entries with full content (for duplicate detection)
@adapter.all_entries
# Returns: Hash<String, Core::Entry>
#   { "concept/ruby/classes.md" => Entry(...), ... }
```

### Optional Method (Highly Recommended)

```ruby
# ALL_ENTRIES - Required for duplicate detection and relationship discovery
def all_entries
  entries = {}

  @adapter.list.each do |entry_info|
    entries[entry_info[:path]] = @adapter.read_entry(file_path: entry_info[:path])
  end

  entries
end
```

**Why it's needed:**
- Used by `find_duplicates` to compare all entry pairs
- Used by `find_related` to build knowledge graph
- Used by `link_related_active` to update relationship metadata
- Without it: Defrag operations limited to analysis only

---

## 3. How MemoryDefrag Works

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│ MemoryDefrag Tool (RubyLLM::Tool)                      │
│ • Agent-facing interface                                │
│ • Parameter validation                                  │
│ • Action routing                                        │
└────────────────┬────────────────────────────────────────┘
                 │
                 │ Delegates to
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ Optimization::Defragmenter                              │
│ • Core optimization logic                               │
│ • Duplicate detection (Jaccard + cosine similarity)    │
│ • Quality scoring (metadata-based)                     │
│ • Merge strategies (keep_newer, keep_larger, combine)  │
│ • Link creation (bidirectional)                        │
└────────────────┬────────────────────────────────────────┘
                 │
                 │ Uses
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ Optimization::Analyzer                                  │
│ • Health score calculation (0-100)                     │
│ • Coverage metrics (metadata, tags, links, embeddings) │
│ • Distribution analysis (by type, confidence)          │
└─────────────────────────────────────────────────────────┘
```

### Operations

#### Read-Only Analysis (Safe)

**1. analyze** - Overall health report
```ruby
MemoryDefrag(action: "analyze")
```
- Calculates health score (0-100)
- Shows metadata coverage, embedding coverage, tag usage
- Breaks down by type (concept, fact, skill, experience)
- Breaks down by confidence (high, medium, low)

**2. find_duplicates** - Identify similar entries
```ruby
MemoryDefrag(action: "find_duplicates", similarity_threshold: 0.85)
```
- Uses **Jaccard similarity** (text-based) + **Cosine similarity** (embedding-based)
- Takes highest similarity score
- Default threshold: 85%
- Returns pairs with similarity scores

**3. find_low_quality** - Find entries with poor metadata
```ruby
MemoryDefrag(action: "find_low_quality", confidence_filter: "low")
```
- Scores quality 0-100 based on metadata completeness
- Flags: no metadata, low confidence, no tags, no links, not embedded
- Helps identify entries to improve or delete

**4. find_archival_candidates** - Find old, unused entries
```ruby
MemoryDefrag(action: "find_archival_candidates", age_days: 90)
```
- Lists entries not updated in N days
- Candidates for deletion or archival
- Default: 90 days

**5. find_related** - Discover entries that should be linked
```ruby
MemoryDefrag(action: "find_related", min_similarity: 0.60, max_similarity: 0.85)
```
- Finds pairs with 60-85% semantic similarity (related but not duplicates)
- Uses **pure semantic similarity** (no keyword boost)
- Shows current linking status (unlinked, one-way, bidirectional)

#### Active Optimization (Modifies Memory)

**CRITICAL:** All active operations default to `dry_run=true` for safety!

**6. link_related** - Create bidirectional links
```ruby
# Preview first
MemoryDefrag(action: "link_related", min_similarity: 0.60, max_similarity: 0.85, dry_run: true)

# Execute after review
MemoryDefrag(action: "link_related", dry_run: false)
```
- Finds related entries (60-85% similarity)
- Updates `related` metadata arrays
- Creates bidirectional links (`memory://path1` ↔ `memory://path2`)
- Skips already-linked pairs

**7. merge_duplicates** - Merge similar entries
```ruby
# Preview first
MemoryDefrag(action: "merge_duplicates", similarity_threshold: 0.85, dry_run: true)

# Execute
MemoryDefrag(action: "merge_duplicates", merge_strategy: "keep_newer", dry_run: false)
```
- Merges duplicate entries
- Strategies:
  - `keep_newer`: Keep most recently updated
  - `keep_larger`: Keep larger content
  - `combine`: Merge both contents
- Creates **stub files** with auto-redirect

**8. cleanup_stubs** - Remove old redirect stubs
```ruby
MemoryDefrag(action: "cleanup_stubs", age_days: 30, max_hits: 3, dry_run: false)
```
- Deletes stub files that are old AND rarely accessed
- Default: 90 days old, max 10 hits
- Keeps frequently-accessed stubs

**9. compact** - Delete low-value entries
```ruby
MemoryDefrag(action: "compact", min_quality_score: 20, min_age_days: 30, max_hits: 0, dry_run: false)
```
- **PERMANENTLY deletes** entries matching ALL criteria:
  - Quality score < threshold
  - Age > min_age_days
  - Hits <= max_hits
- Frees up storage space

**10. full** - Complete optimization workflow
```ruby
# Preview
MemoryDefrag(action: "full", dry_run: true)

# Execute
MemoryDefrag(action: "full", dry_run: false)
```
- Runs: `merge_duplicates` → `cleanup_stubs` → `compact`
- Shows health score improvement
- **ALWAYS preview first!**
- Does NOT include `link_related` (run separately)

### Similarity Algorithms

#### Jaccard Similarity (Text-based)

```ruby
# lib/swarm_memory/search/text_similarity.rb
def self.jaccard(text1, text2)
  # Tokenize into words
  words1 = text1.downcase.scan(/\w+/)
  words2 = text2.downcase.scan(/\w+/)

  # Calculate Jaccard coefficient
  set1 = Set.new(words1)
  set2 = Set.new(words2)

  intersection = (set1 & set2).size
  union = (set1 | set2).size

  return 0.0 if union.zero?
  intersection.to_f / union
end
```

**Use case:** Fast, always available (no embeddings needed)

#### Cosine Similarity (Embedding-based)

```ruby
# lib/swarm_memory/search/text_similarity.rb
def self.cosine(vector1, vector2)
  dot_product = vector1.zip(vector2).sum { |a, b| a * b }
  magnitude1 = Math.sqrt(vector1.sum { |x| x**2 })
  magnitude2 = Math.sqrt(vector2.sum { |x| x**2 })

  return 0.0 if magnitude1.zero? || magnitude2.zero?
  dot_product / (magnitude1 * magnitude2)
end
```

**Use case:** More accurate semantic similarity, requires embeddings

#### Hybrid Approach

```ruby
# lib/swarm_memory/optimization/defragmenter.rb:68
text_sim = Search::TextSimilarity.jaccard(entry1.content, entry2.content)
semantic_sim = if entry1.embedded? && entry2.embedded?
  Search::TextSimilarity.cosine(entry1.embedding, entry2.embedding)
end

# Use highest similarity score
similarity = [text_sim, semantic_sim].compact.max
```

**Result:** Best of both worlds - works without embeddings, more accurate with them

### Quality Scoring

Metadata-based quality score (0-100):

```ruby
def calculate_quality_from_metadata(metadata)
  score = 0

  score += 20 if metadata["type"]              # Has type
  score += 20 if metadata["confidence"]        # Has confidence
  score += 15 unless metadata["tags"].empty?   # Has tags
  score += 15 unless metadata["related"].empty? # Has links
  score += 10 if metadata["domain"]            # Has domain
  score += 10 if metadata["last_verified"]     # Has verification
  score += 10 if metadata["confidence"] == "high" # High confidence

  score
end
```

### Health Score Calculation

Overall memory health (0-100):

```ruby
score = 0

# Metadata coverage (30 points)
score += 30 if frontmatter_pct > 80
score += 20 if frontmatter_pct > 50

# Tags coverage (20 points)
score += 20 if tags_pct > 60
score += 10 if tags_pct > 30

# Links coverage (20 points)
score += 20 if links_pct > 40
score += 10 if links_pct > 20

# Embedding coverage (15 points)
score += 15 if embedding_pct > 80
score += 8 if embedding_pct > 50

# High confidence ratio (15 points)
score += 15 if high_confidence_pct > 50
score += 8 if high_confidence_pct > 25
```

**Interpretation:**
- **80-100**: Excellent - well-organized
- **60-79**: Good - decent but improvable
- **40-59**: Fair - needs defrag
- **20-39**: Poor - significant cleanup needed
- **0-19**: Critical - immediate attention required

### Stub Files

When entries are merged or moved, MemoryDefrag creates **stub files** that automatically redirect:

```ruby
def create_stub(from:, to:, reason:)
  stub_content = "# #{reason} → #{to}\n\nThis entry was #{reason} into #{to}."

  @adapter.write(
    file_path: from,
    content: stub_content,
    title: "[STUB] → #{to}",
    metadata: {
      "stub" => true,
      "redirect_to" => to,
      "reason" => reason  # "merged" or "moved"
    }
  )
end
```

**Detection:**
```ruby
# Storage#read_entry automatically follows redirects
if entry.metadata["stub"] == true
  redirect_target = entry.metadata["redirect_to"]
  return read_entry(file_path: redirect_target, visited: visited + [normalized_path])
end
```

**Cleanup:**
- Stubs older than N days AND rarely accessed (< N hits) can be cleaned up
- Default: 90 days old, max 10 hits
- Keeps frequently-accessed stubs even if old

---

## 4. Usage Patterns

### Agent Workflow

```ruby
# 1. Check health
MemoryDefrag(action: "analyze")
# Output: Health score 65/100

# 2. Find issues
MemoryDefrag(action: "find_duplicates")
# Output: Found 3 duplicate pairs

MemoryDefrag(action: "find_low_quality")
# Output: Found 5 entries with quality issues

# 3. Preview fixes
MemoryDefrag(action: "merge_duplicates", dry_run: true)
# Output: Would merge 3 pairs

# 4. Execute if preview looks good
MemoryDefrag(action: "merge_duplicates", dry_run: false)
# Output: Merged 3 pairs, freed 12.5KB

# 5. Verify improvement
MemoryDefrag(action: "analyze")
# Output: Health score 75/100 (+10)
```

### Maintenance Schedule

```ruby
# Light check (every 15-20 new entries)
MemoryDefrag(action: "analyze")

# Medium check (every 50 entries)
MemoryDefrag(action: "analyze")
MemoryDefrag(action: "find_duplicates")
MemoryDefrag(action: "find_low_quality")

# Heavy maintenance (every 100 entries)
MemoryDefrag(action: "full", dry_run: true)   # Preview
MemoryDefrag(action: "full", dry_run: false)  # Execute
```

### Tool Invocation

MemoryDefrag is available as a **memory tool** when memory is enabled:

```ruby
# Automatically added to agents with memory configured
agent :assistant do
  memory do
    directory ".swarm/assistant-memory"
    mode :researcher  # MemoryDefrag included
  end
end

# Tool modes:
# - :assistant - MemoryDefrag NOT included (too advanced)
# - :researcher - MemoryDefrag included (all optimization tools)
# - :retrieval - MemoryDefrag NOT included (read-only mode)
```

---

## 5. Adapter Compatibility

### Minimum Requirements

To support MemoryDefrag **analysis operations** (read-only):

✅ **REQUIRED:**
```ruby
def list(prefix: nil)
  # Return array of entry metadata
end

def read_entry(file_path:)
  # Return Core::Entry with metadata
end

def total_size
  # Return total storage size in bytes
end
```

✅ **OPTIONAL but RECOMMENDED:**
```ruby
def all_entries
  # Return hash of path => Entry for duplicate detection
end
```

### Full Compatibility

To support MemoryDefrag **active operations** (modification):

✅ **REQUIRED:**
```ruby
def write(file_path:, content:, title:, embedding: nil, metadata: nil)
  # Write/update entry
end

def delete(file_path:)
  # Delete entry permanently
end

def all_entries
  # Required for merge and link operations
end
```

### Implementation Checklist

- [ ] `list(prefix:)` returns `Array<Hash>` with `:path`, `:title`, `:size`, `:updated_at`
- [ ] `read_entry(file_path:)` returns `Core::Entry` with all 6 fields
- [ ] `write(...)` updates existing entries (upsert behavior)
- [ ] `delete(file_path:)` permanently removes entries
- [ ] `total_size` returns current storage size in bytes
- [ ] `all_entries` returns `Hash<String, Core::Entry>` (recommended)
- [ ] Entry metadata uses **string keys** (not symbols)
- [ ] Entry metadata includes: `type`, `confidence`, `tags`, `related`, `domain`
- [ ] Stub detection: check `metadata["stub"] == true` and `metadata["redirect_to"]`

### Metadata Requirements

MemoryDefrag expects entries to have metadata with **string keys**:

```ruby
metadata = {
  "type" => "concept",           # Required for categorization
  "confidence" => "high",         # Required for quality scoring
  "tags" => ["ruby", "oop"],      # Required for quality scoring
  "related" => [                  # Optional, used by link operations
    "memory://concept/ruby/modules.md"
  ],
  "domain" => "programming/ruby", # Optional, used by quality scoring
  "last_verified" => "2024-01-15", # Optional, used by quality scoring
  "hits" => 5,                     # Optional, tracks read count
  "stub" => false,                 # Internal, set by merge operations
  "redirect_to" => nil             # Internal, set by merge operations
}
```

**IMPORTANT:** Keys must be **strings**, not symbols!

---

## 6. PostgreSQL Implementation

### Database Requirements

Your PostgreSQL schema should support:

```sql
CREATE TABLE agent_memories (
  id BIGSERIAL PRIMARY KEY,
  file_path VARCHAR(500) NOT NULL UNIQUE,
  content TEXT NOT NULL,
  title VARCHAR(200) NOT NULL,
  embedding vector(384),
  metadata JSONB NOT NULL,  -- ← CRITICAL for MemoryDefrag
  size INTEGER NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_file_path ON agent_memories(file_path);
CREATE INDEX idx_updated_at ON agent_memories(updated_at DESC);

-- GIN index for metadata queries
CREATE INDEX idx_metadata ON agent_memories USING GIN(metadata);
CREATE INDEX idx_metadata_type ON agent_memories((metadata->>'type'));
CREATE INDEX idx_metadata_stub ON agent_memories((metadata->>'stub'));

-- Vector index for semantic duplicate detection
CREATE INDEX idx_embedding ON agent_memories
  USING hnsw (embedding vector_cosine_ops);
```

### Adapter Implementation

```ruby
class PostgresAdapter < SwarmMemory::Adapters::Base
  # ... standard methods ...

  # ALL_ENTRIES - Required for MemoryDefrag duplicate/link operations
  def all_entries
    result = @connection.exec("SELECT * FROM agent_memories ORDER BY file_path")

    entries = {}
    result.each do |row|
      # Parse embedding
      embedding = if row['embedding']
        row['embedding'].tr('[]', '').split(',').map(&:to_f)
      end

      # Parse metadata (CRITICAL: ensure string keys)
      metadata = if row['metadata']
        JSON.parse(row['metadata'])  # JSON.parse returns string keys ✅
      else
        {}
      end

      entries[row['file_path']] = SwarmMemory::Core::Entry.new(
        content: row['content'],
        title: row['title'],
        updated_at: Time.parse(row['updated_at']),
        size: row['size'].to_i,
        embedding: embedding,
        metadata: metadata  # String keys from JSON.parse
      )
    end

    entries
  end

  # LIST - Used by health analysis
  def list(prefix: nil)
    sql = "SELECT file_path, title, size, updated_at FROM agent_memories"
    params = []

    if prefix
      sql += " WHERE file_path LIKE $1"
      params << "#{prefix}%"
    end

    sql += " ORDER BY file_path"
    result = @connection.exec_params(sql, params)

    result.map do |row|
      {
        path: row['file_path'],
        title: row['title'],
        size: row['size'].to_i,
        updated_at: Time.parse(row['updated_at'])
      }
    end
  end

  # READ_ENTRY - Used by quality analysis
  def read_entry(file_path:)
    result = @connection.exec_params(
      "SELECT * FROM agent_memories WHERE file_path = $1",
      [file_path]
    )

    raise ArgumentError, "memory://#{file_path} not found" if result.ntuples == 0

    row = result[0]

    # Parse embedding
    embedding = row['embedding'] ? row['embedding'].tr('[]', '').split(',').map(&:to_f) : nil

    # Parse metadata (string keys)
    metadata = row['metadata'] ? JSON.parse(row['metadata']) : {}

    SwarmMemory::Core::Entry.new(
      content: row['content'],
      title: row['title'],
      updated_at: Time.parse(row['updated_at']),
      size: row['size'].to_i,
      embedding: embedding,
      metadata: metadata  # String keys ✅
    )
  end

  # WRITE - Used by merge and link operations
  def write(file_path:, content:, title:, embedding: nil, metadata: nil)
    # Validate size limits
    content_size = content.bytesize
    raise ArgumentError, "Content exceeds maximum size" if content_size > MAX_ENTRY_SIZE

    # Prepare embedding for pgvector
    embedding_sql = embedding ? "[#{embedding.join(',')}]" : "NULL"

    # Ensure metadata has string keys (defensive)
    metadata_hash = metadata ? Utils.stringify_keys(metadata) : {}

    # Upsert
    result = @connection.exec_params(
      <<~SQL,
        INSERT INTO agent_memories
          (file_path, content, title, embedding, metadata, size)
        VALUES ($1, $2, $3, $4::vector, $5, $6)
        ON CONFLICT (file_path) DO UPDATE SET
          content = EXCLUDED.content,
          title = EXCLUDED.title,
          embedding = EXCLUDED.embedding,
          metadata = EXCLUDED.metadata,
          size = EXCLUDED.size,
          updated_at = NOW()
        RETURNING updated_at
      SQL
      [file_path, content, title, embedding_sql, metadata_hash.to_json, content_size]
    )

    SwarmMemory::Core::Entry.new(
      content: content,
      title: title,
      updated_at: Time.parse(result[0]['updated_at']),
      size: content_size,
      embedding: embedding,
      metadata: metadata_hash
    )
  end

  # DELETE - Used by cleanup and compact operations
  def delete(file_path:)
    result = @connection.exec_params(
      "DELETE FROM agent_memories WHERE file_path = $1 RETURNING size",
      [file_path]
    )

    raise ArgumentError, "memory://#{file_path} not found" if result.ntuples == 0
  end

  # TOTAL_SIZE - Used by health report
  def total_size
    result = @connection.exec_params(
      "SELECT COALESCE(SUM(size), 0) as total FROM agent_memories",
      []
    )
    result[0]['total'].to_i
  end
end
```

### Performance Optimization

For large memory stores (1000+ entries), optimize `all_entries`:

```ruby
def all_entries
  # Use cursor for memory efficiency
  entries = {}

  @connection.exec("DECLARE entry_cursor CURSOR FOR SELECT * FROM agent_memories")

  loop do
    result = @connection.exec("FETCH 100 FROM entry_cursor")
    break if result.ntuples == 0

    result.each do |row|
      # ... parse row ...
      entries[row['file_path']] = entry
    end
  end

  @connection.exec("CLOSE entry_cursor")
  entries
end
```

### Multi-Bank Support

For multi-bank adapters, filter by bank:

```ruby
def all_entries
  # Only load entries for current/default bank
  bank_filter = @current_bank || @default_bank

  result = @connection.exec_params(
    "SELECT * FROM agent_memories WHERE bank = $1",
    [bank_filter]
  )

  # ... parse results ...
end
```

---

## Summary

### Key Takeaways

1. **MemoryDefrag is a maintenance tool** - analyzes and optimizes memory quality
2. **Uses standard adapter interface** - no special methods required (except `all_entries`)
3. **Safe by default** - active operations require `dry_run=false` to execute
4. **Metadata-based** - quality scoring, duplicate detection, relationship discovery
5. **Hybrid similarity** - Jaccard (text) + Cosine (embeddings) for best accuracy
6. **Stub redirects** - merged entries leave redirects for backward compatibility
7. **Health scoring** - 0-100 score based on metadata coverage and quality

### Adapter Checklist

To ensure full MemoryDefrag compatibility:

- [ ] Implement `all_entries()` returning `Hash<String, Core::Entry>`
- [ ] Ensure `list()` returns entries with `:updated_at`
- [ ] Ensure `read_entry()` includes metadata with **string keys**
- [ ] Ensure `write()` supports upsert (update existing entries)
- [ ] Ensure `delete()` permanently removes entries
- [ ] Ensure `total_size()` returns accurate byte count
- [ ] Store metadata with: `type`, `confidence`, `tags`, `related`, `domain`
- [ ] Support stub metadata: `stub`, `redirect_to`, `reason`
- [ ] Test all 10 MemoryDefrag actions (5 read-only + 5 active)

### PostgreSQL-Specific

- ✅ Use JSONB for metadata storage (efficient, indexable)
- ✅ Add GIN index on metadata for fast queries
- ✅ Use `JSON.parse()` for string keys (not `YAML.load`)
- ✅ Store embeddings as `vector(384)` for semantic duplicate detection
- ✅ Add HNSW index on embeddings for performance
- ✅ Use cursor for `all_entries` on large datasets (1000+ entries)

Your PostgreSQL adapters are **fully compatible** with MemoryDefrag if they implement the standard adapter interface correctly! 🎉
