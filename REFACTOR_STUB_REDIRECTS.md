# Refactor: Move Stub Redirect Logic to Storage Layer

## Overview

Move stub redirect following logic from `FilesystemAdapter` to `Storage` layer to make it adapter-agnostic and ensure all memory adapters handle redirects consistently.

## Problem Statement

**Current Implementation:**
- Redirect logic is implemented in `FilesystemAdapter` (lines 174-178, 208-212)
- Uses content parsing (`# merged →`, `# moved →`) to detect stubs
- Any new adapter (PostgreSQL, Redis, S3, etc.) must re-implement this logic
- Violates single responsibility principle

**Why This is Wrong:**
- Adapters should focus on storage mechanics (read/write/delete)
- Storage layer should handle cross-cutting concerns like redirects
- Metadata already contains redirect info (`stub: true`, `redirect_to: path`)
- Future adapters shouldn't need to parse content for redirects

## Solution

Move redirect detection and following to `Storage` layer using metadata-based detection.

### Key Design Decisions

1. **Metadata-based detection**: Use `metadata["stub"] == true` instead of content parsing
2. **Recursive following**: Follow redirect chains transparently
3. **Visited tracking**: Detect circular redirects immediately by tracking visited paths
4. **Depth limit**: Max 5 redirects before requiring maintenance
5. **Clear error messages**: Help users understand what went wrong

## Files to Modify

### 1. `lib/swarm_memory/core/storage.rb`

#### Modify `read_entry()` method (currently lines 111-114)

**Before:**
```ruby
def read_entry(file_path:)
  normalized_path = PathNormalizer.normalize(file_path)
  @adapter.read_entry(file_path: normalized_path)
end
```

**After:**
```ruby
# Read full entry with metadata, automatically following stub redirects
#
# @param file_path [String] Path to read from
# @param _visited [Array<String>] Internal: tracks visited paths to detect circular redirects
# @return [Entry] Full entry object
# @raise [ArgumentError] If path not found, circular redirect detected, or too many redirects
def read_entry(file_path:, _visited: [])
  normalized_path = PathNormalizer.normalize(file_path)

  # Detect circular redirects immediately
  if _visited.include?(normalized_path)
    cycle = _visited + [normalized_path]
    raise ArgumentError,
      "Circular redirect detected in memory storage: #{cycle.join(" → ")}\n\n" \
      "This indicates corrupted stub files. Please run MemoryDefrag to repair:\n" \
      "  MemoryDefrag(action: \"analyze\")"
  end

  # Check depth limit (prevent infinite chains)
  if _visited.size >= 5
    chain = _visited + [normalized_path]
    raise ArgumentError,
      "Memory redirect chain too deep (>5 redirects): #{chain.join(" → ")}\n\n" \
      "This indicates fragmented memory storage. Please run maintenance:\n" \
      "  MemoryDefrag(action: \"full\", dry_run: true)  # Preview first\n" \
      "  MemoryDefrag(action: \"full\", dry_run: false) # Execute"
  end

  # Read entry from adapter
  begin
    entry = @adapter.read_entry(file_path: normalized_path)
  rescue ArgumentError => e
    # If this is a redirect target that doesn't exist, provide helpful error
    if !_visited.empty?
      original_path = _visited.first
      raise ArgumentError,
        "memory://#{original_path} was redirected to memory://#{normalized_path}, but the target was not found.\n\n" \
        "The original entry may have been merged or moved incorrectly. " \
        "Run MemoryDefrag to identify and fix broken redirects:\n" \
        "  MemoryDefrag(action: \"analyze\")"
    else
      # Not a redirect, just re-raise original error
      raise
    end
  end

  # Check if this is a stub redirect
  if entry.metadata && entry.metadata["stub"] == true
    redirect_target = entry.metadata["redirect_to"]

    # Validate redirect target exists
    if redirect_target.nil? || redirect_target.strip.empty?
      raise ArgumentError,
        "memory://#{normalized_path} is a stub with invalid redirect metadata.\n\n" \
        "This should never happen (stubs are created by MemoryDefrag). " \
        "The stub file may be corrupted. Please report this as a bug."
    end

    # Follow redirect recursively, tracking visited paths
    return read_entry(file_path: redirect_target, _visited: _visited + [normalized_path])
  end

  # Not a stub, return the entry
  entry
end
```

#### Modify `read()` method (currently lines 102-105)

**Before:**
```ruby
def read(file_path:)
  normalized_path = PathNormalizer.normalize(file_path)
  @adapter.read(file_path: normalized_path)
end
```

**After:**
```ruby
# Read content from storage, automatically following stub redirects
#
# @param file_path [String] Path to read from
# @return [String] Content at the path
def read(file_path:)
  entry = read_entry(file_path: file_path)
  entry.content
end
```

### 2. `lib/swarm_memory/adapters/filesystem_adapter.rb`

#### Remove redirect logic from `read()` method (lines 156-184)

**Remove lines 174-178:**
```ruby
# Check if it's a stub (redirect)
if stub_content?(content)
  target_path = extract_redirect_target(content)
  return read(file_path: target_path) if target_path
end
```

**Keep:**
- Line 181: `increment_hits(file_path)` - Still needed
- Line 183: `content` - Return the content as-is

**Result:**
```ruby
def read(file_path:)
  raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?

  # Check for virtual built-in entries first
  if VIRTUAL_ENTRIES.key?(file_path)
    entry = load_virtual_entry(file_path)
    return entry.content
  end

  # Strip .md extension and flatten path
  base_path = file_path.sub(/\.md\z/, "")
  disk_path = flatten_path(base_path)
  md_file = File.join(@directory, "#{disk_path}.md")

  raise ArgumentError, "memory://#{file_path} not found" unless File.exist?(md_file)

  content = File.read(md_file)

  # Increment hit counter
  increment_hits(file_path)

  content
end
```

#### Remove redirect logic from `read_entry()` method (lines 190-234)

**Remove lines 208-212:**
```ruby
# Follow stub redirect if applicable
if stub_content?(content)
  target_path = extract_redirect_target(content)
  return read_entry(file_path: target_path) if target_path
end
```

**Keep:**
- Line 224: `increment_hits(file_path)` - Still needed
- Lines 226-233: Entry construction - Return the entry as-is

**Result:**
```ruby
def read_entry(file_path:)
  raise ArgumentError, "file_path is required" if file_path.nil? || file_path.to_s.strip.empty?

  # Check for virtual built-in entries first
  if VIRTUAL_ENTRIES.key?(file_path)
    return load_virtual_entry(file_path)
  end

  # Strip .md extension and flatten path
  base_path = file_path.sub(/\.md\z/, "")
  disk_path = flatten_path(base_path)
  md_file = File.join(@directory, "#{disk_path}.md")
  yaml_file = File.join(@directory, "#{disk_path}.yml")

  raise ArgumentError, "memory://#{file_path} not found" unless File.exist?(md_file)

  content = File.read(md_file)

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
```

#### Keep stub utility methods (still used by list/glob)

**Do NOT remove these methods:**
- `stub_content?()` - line 542
- `stub_file?()` - line 550
- `extract_redirect_target()` - line 564

These are still used to skip stubs in listing operations.

### 3. `lib/swarm_memory/optimization/defragmenter.rb`

#### Ensure stub metadata is always valid (line 750)

**Current implementation is already correct:**
```ruby
def create_stub(from:, to:, reason:)
  stub_content = "# #{reason} → #{to}\n\nThis entry was #{reason} into #{to}."

  @adapter.write(
    file_path: from,
    content: stub_content,
    title: "[STUB] → #{to}",
    metadata: { "stub" => true, "redirect_to" => to, "reason" => reason },
  )
end
```

**Validation to add:**
```ruby
def create_stub(from:, to:, reason:)
  raise ArgumentError, "Cannot create stub without target path" if to.nil? || to.strip.empty?
  raise ArgumentError, "Cannot create stub without reason" if reason.nil? || reason.strip.empty?

  stub_content = "# #{reason} → #{to}\n\nThis entry was #{reason} into #{to}."

  @adapter.write(
    file_path: from,
    content: stub_content,
    title: "[STUB] → #{to}",
    metadata: { "stub" => true, "redirect_to" => to, "reason" => reason },
  )
end
```

## Error Handling

### 1. Missing Redirect Target

**When:** Following a redirect to a non-existent entry

**Error Message:**
```
memory://concept/ruby/old-classes.md was redirected to memory://concept/ruby/classes.md, but the target was not found.

The original entry may have been merged or moved incorrectly. Run MemoryDefrag to identify and fix broken redirects:
  MemoryDefrag(action: "analyze")
```

### 2. Circular Redirects

**When:** A→B→A or any cycle detected

**Detection:** Track all visited paths, detect immediately when we see a duplicate

**Error Message:**
```
Circular redirect detected in memory storage: concept/a.md → concept/b.md → concept/a.md

This indicates corrupted stub files. Please run MemoryDefrag to repair:
  MemoryDefrag(action: "analyze")
```

### 3. Malformed Metadata

**When:** Stub has `stub: true` but missing/empty `redirect_to`

**Should Never Happen:** Defrag creates these, so this is a bug

**Error Message:**
```
memory://concept/ruby/old.md is a stub with invalid redirect metadata.

This should never happen (stubs are created by MemoryDefrag). The stub file may be corrupted. Please report this as a bug.
```

### 4. Redirect Chain Too Deep

**When:** More than 5 redirects in chain

**Error Message:**
```
Memory redirect chain too deep (>5 redirects): concept/a.md → concept/b.md → concept/c.md → concept/d.md → concept/e.md → concept/f.md

This indicates fragmented memory storage. Please run maintenance:
  MemoryDefrag(action: "full", dry_run: true)  # Preview first
  MemoryDefrag(action: "full", dry_run: false) # Execute
```

## Testing Plan

### Unit Tests for `Storage#read_entry`

```ruby
# test/swarm_memory/core/storage_test.rb

def test_read_entry_follows_single_redirect
  # Create entry B
  storage.write(file_path: "concept/b.md", content: "Final content", title: "B")

  # Create stub A → B
  adapter.write(
    file_path: "concept/a.md",
    content: "# merged → concept/b.md",
    title: "[STUB] → concept/b.md",
    metadata: { "stub" => true, "redirect_to" => "concept/b.md", "reason" => "merged" }
  )

  # Reading A should return B's content
  entry = storage.read_entry(file_path: "concept/a.md")
  assert_equal "Final content", entry.content
  assert_equal "B", entry.title
end

def test_read_entry_follows_chain_of_redirects
  # Create entry D (final)
  storage.write(file_path: "concept/d.md", content: "Final", title: "D")

  # Create chain: A → B → C → D
  adapter.write(file_path: "concept/c.md", ..., metadata: { "stub" => true, "redirect_to" => "concept/d.md" })
  adapter.write(file_path: "concept/b.md", ..., metadata: { "stub" => true, "redirect_to" => "concept/c.md" })
  adapter.write(file_path: "concept/a.md", ..., metadata: { "stub" => true, "redirect_to" => "concept/b.md" })

  # Reading A should return D
  entry = storage.read_entry(file_path: "concept/a.md")
  assert_equal "Final", entry.content
end

def test_read_entry_detects_circular_redirect_immediate
  # Create A → B
  adapter.write(
    file_path: "concept/a.md",
    content: "# merged → concept/b.md",
    title: "[STUB]",
    metadata: { "stub" => true, "redirect_to" => "concept/b.md" }
  )

  # Create B → A (circular!)
  adapter.write(
    file_path: "concept/b.md",
    content: "# merged → concept/a.md",
    title: "[STUB]",
    metadata: { "stub" => true, "redirect_to" => "concept/a.md" }
  )

  # Should detect cycle immediately
  error = assert_raises(ArgumentError) { storage.read_entry(file_path: "concept/a.md") }
  assert_includes error.message, "Circular redirect detected"
  assert_includes error.message, "concept/a.md → concept/b.md → concept/a.md"
end

def test_read_entry_fails_on_missing_redirect_target
  # Create stub A → B (but B doesn't exist)
  adapter.write(
    file_path: "concept/a.md",
    content: "# merged → concept/b.md",
    title: "[STUB]",
    metadata: { "stub" => true, "redirect_to" => "concept/b.md" }
  )

  # Should provide helpful error
  error = assert_raises(ArgumentError) { storage.read_entry(file_path: "concept/a.md") }
  assert_includes error.message, "was redirected to memory://concept/b.md, but the target was not found"
  assert_includes error.message, "MemoryDefrag"
end

def test_read_entry_fails_on_chain_too_deep
  # Create chain: A → B → C → D → E → F (6 redirects, exceeds limit of 5)
  storage.write(file_path: "concept/f.md", content: "Final", title: "F")
  adapter.write(file_path: "concept/e.md", ..., metadata: { "stub" => true, "redirect_to" => "concept/f.md" })
  adapter.write(file_path: "concept/d.md", ..., metadata: { "stub" => true, "redirect_to" => "concept/e.md" })
  adapter.write(file_path: "concept/c.md", ..., metadata: { "stub" => true, "redirect_to" => "concept/d.md" })
  adapter.write(file_path: "concept/b.md", ..., metadata: { "stub" => true, "redirect_to" => "concept/c.md" })
  adapter.write(file_path: "concept/a.md", ..., metadata: { "stub" => true, "redirect_to" => "concept/b.md" })

  # Should fail with maintenance suggestion
  error = assert_raises(ArgumentError) { storage.read_entry(file_path: "concept/a.md") }
  assert_includes error.message, "too deep (>5 redirects)"
  assert_includes error.message, "MemoryDefrag"
end

def test_read_entry_fails_on_malformed_stub_metadata
  # Create stub with missing redirect_to
  adapter.write(
    file_path: "concept/a.md",
    content: "# merged → somewhere",
    title: "[STUB]",
    metadata: { "stub" => true, "redirect_to" => nil } # Invalid!
  )

  error = assert_raises(ArgumentError) { storage.read_entry(file_path: "concept/a.md") }
  assert_includes error.message, "invalid redirect metadata"
  assert_includes error.message, "should never happen"
end

def test_read_delegates_to_read_entry
  storage.write(file_path: "concept/a.md", content: "Test content", title: "A")

  content = storage.read(file_path: "concept/a.md")
  assert_equal "Test content", content
end

def test_read_follows_redirects
  storage.write(file_path: "concept/b.md", content: "Final content", title: "B")
  adapter.write(
    file_path: "concept/a.md",
    content: "# merged → concept/b.md",
    title: "[STUB]",
    metadata: { "stub" => true, "redirect_to" => "concept/b.md" }
  )

  content = storage.read(file_path: "concept/a.md")
  assert_equal "Final content", content
end
```

### Integration Tests

```ruby
# test/swarm_memory/tools/memory_read_test.rb

def test_memory_read_follows_redirects_transparently
  # Create final entry
  memory_write.execute(
    file_path: "concept/ruby/classes.md",
    content: "# Ruby Classes\n\nClasses are blueprints...",
    title: "Ruby Classes"
  )

  # Simulate merge: create stub for old path
  storage.adapter.write(
    file_path: "concept/ruby/old-classes.md",
    content: "# merged → concept/ruby/classes.md",
    title: "[STUB] → concept/ruby/classes.md",
    metadata: { "stub" => true, "redirect_to" => "concept/ruby/classes.md", "reason" => "merged" }
  )

  # Reading old path should transparently return new content
  result = memory_read.execute(file_path: "concept/ruby/old-classes.md")
  json = JSON.parse(result)

  assert_includes json["content"], "Classes are blueprints"
  assert_equal "Ruby Classes", json["metadata"]["title"]
end
```

## Implementation Steps

1. **Add validation to `Defragmenter#create_stub`**
   - Ensure `to` and `reason` are never nil/empty
   - This prevents malformed stubs from being created

2. **Modify `Storage#read_entry`**
   - Add `_visited` parameter for tracking visited paths
   - Add circular redirect detection
   - Add depth limit check
   - Add stub redirect following with metadata detection
   - Add helpful error messages for each failure case

3. **Simplify `Storage#read`**
   - Delegate to `read_entry` and return content
   - All redirect logic handled by `read_entry`

4. **Remove redirect logic from `FilesystemAdapter#read`**
   - Keep hit tracking
   - Remove content parsing and redirect following

5. **Remove redirect logic from `FilesystemAdapter#read_entry`**
   - Keep hit tracking
   - Remove content parsing and redirect following

6. **Run tests**
   - Ensure existing tests pass (behavior unchanged)
   - Add new tests for edge cases

7. **Verify integration**
   - Test with MemoryRead tool
   - Test with defrag operations
   - Test with various redirect scenarios

## Benefits

1. **Adapter-agnostic**: Any adapter (PostgreSQL, Redis, S3) gets redirects for free
2. **Metadata-based**: No content parsing needed
3. **Single source of truth**: Redirect logic in one place (`Storage` layer)
4. **Better error handling**: Clear, actionable error messages
5. **Circular redirect protection**: Immediate detection with helpful diagnostics
6. **Depth limit**: Prevents infinite chains and suggests maintenance
7. **Cleaner separation**: Adapters focus on storage, Storage handles orchestration

## Migration Notes

**No migration required!**

- Existing stub files will work (they already have correct metadata)
- Behavior is identical from user perspective
- All existing tests should pass without changes
- This is purely an internal refactoring

## Future Enhancements

1. **MemoryDefrag action to fix broken redirects**
   - Scan for stubs with missing targets
   - Scan for circular redirects
   - Report and optionally fix

2. **MemoryDefrag action to flatten redirect chains**
   - Find chains > 2 redirects
   - Update intermediate stubs to point directly to final target
   - Reduces redirect overhead

3. **Analytics**
   - Track redirect depth distribution
   - Identify most-redirected paths
   - Suggest candidates for cleanup
