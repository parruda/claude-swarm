# SwarmMemory Guide

Complete guide to using SwarmMemory for persistent agent knowledge storage with semantic search.

---

## Overview

**SwarmMemory** is a separate gem that provides persistent memory storage for SwarmSDK agents. It enables agents to:

- Store and retrieve knowledge across sessions
- Search memories semantically (hybrid: embeddings + keywords)
- Build skills that adapt agent toolsets dynamically
- Automatically discover relevant knowledge on every user message
- Build knowledge graphs with relationship discovery

**Key Features:**
- 🧠 Persistent storage with semantic search
- 🔍 Hybrid search (50% semantic + 50% keyword matching)
- 🎯 Automatic skill discovery (78% match accuracy)
- 📚 4 memory categories (concept, fact, skill, experience)
- 🔗 Automatic relationship discovery and linking
- 🚀 Fast local embeddings via Informers (ONNX)
- 🔌 Plugin-based integration (zero coupling with SDK)

---

## Installation

SwarmMemory is a **separate gem** that must be installed alongside SwarmSDK.

### Gemfile

```ruby
gem 'swarm_sdk'
gem 'swarm_memory'  # Separate gem
gem 'informers'     # Required for semantic search
```

### Install

```bash
bundle install
```

### Load Order

```ruby
require 'swarm_sdk'
require 'swarm_memory'  # Auto-registers plugin with SwarmSDK
```

**Important:** SwarmMemory must be required AFTER SwarmSDK for auto-registration to work.

---

## Quick Start

### Ruby DSL

```ruby
require 'swarm_sdk'
require 'swarm_memory'

swarm = SwarmSDK.build do
  name "Learning Assistant"
  lead :assistant

  agent :assistant do
    model "claude-sonnet-4"
    description "Learning assistant with persistent memory"

    # Enable memory storage
    memory do
      directory ".swarm/assistant-memory"
    end

    # Memory tools are automatically added
  end
end

result = swarm.execute("Learn about Ruby metaprogramming and remember it")
```

### YAML Configuration

```yaml
version: 2
swarm:
  name: Learning Assistant
  lead: assistant
  agents:
    assistant:
      model: claude-sonnet-4
      description: Learning assistant with persistent memory
      memory:
        directory: .swarm/assistant-memory
```

---

## How It Works

### Plugin Architecture

SwarmMemory integrates with SwarmSDK via the **plugin system**:

```
require 'swarm_memory'
    ↓
Auto-registration: SwarmMemory::Integration::SDKPlugin
    ↓
SwarmSDK::PluginRegistry.register(plugin)
    ↓
Plugin provides:
  - 8 memory tools (MemoryWrite, MemoryRead, etc.)
  - Memory storage (FilesystemAdapter + Embeddings)
  - System prompt contributions
  - Automatic skill discovery on user messages
```

**Zero Coupling:** SwarmSDK has no knowledge of SwarmMemory. It works standalone.

---

## Memory Structure

### 4 Fixed Categories

Memory has **EXACTLY 4** top-level categories. These are **FIXED** - agents cannot create new ones:

```
memory/
├── concept/          # Abstract ideas and mental models
│   └── {domain}/{name}.md
├── fact/             # Concrete, verifiable information
│   └── {subfolder}/{name}.md
├── skill/            # Step-by-step procedures (how-to)
│   └── {domain}/{name}.md
└── experience/       # Lessons learned from outcomes
    └── {name}.md
```

**Examples:**
- ✅ `concept/ruby/classes.md` - Understanding Ruby classes
- ✅ `fact/people/john.md` - Information about John
- ✅ `skill/debugging/api-errors.md` - How to debug API errors
- ✅ `experience/fixed-cors-bug.md` - Lesson from fixing a bug

**Invalid:**
- ❌ `documentation/api.md` - No "documentation/" category exists
- ❌ `reference/guide.md` - No "reference/" category exists
- ❌ `tutorial/intro.md` - No "tutorial/" category exists

---

## Memory Tools

SwarmMemory provides 9 tools automatically added to agents with memory configured:

### Storage Tools

**MemoryWrite** - Store content with structured metadata
```ruby
MemoryWrite(
  file_path: "concept/ruby/classes.md",
  content: "# Ruby Classes\n\nClasses are blueprints...",
  title: "Ruby Classes",
  type: "concept",
  confidence: "high",
  tags: ["ruby", "oop", "classes"],
  related: [],
  domain: "programming/ruby",
  source: "documentation"
)
```

**MemoryRead** - Retrieve stored content
```ruby
MemoryRead(file_path: "concept/ruby/classes.md")
# Returns JSON: {content: "...", metadata: {...}}
```

**MemoryEdit** - Exact string replacement
```ruby
MemoryEdit(
  file_path: "concept/ruby/classes.md",
  old_string: "Classes are blueprints",
  new_string: "Classes are templates"
)
```

**MemoryMultiEdit** - Multiple edits in one operation
```ruby
MemoryMultiEdit(
  file_path: "concept/ruby/classes.md",
  edits_json: '[
    {"old_string": "foo", "new_string": "bar"},
    {"old_string": "baz", "new_string": "qux"}
  ]'
)
```

**MemoryDelete** - Remove entries
```ruby
MemoryDelete(file_path: "concept/old-api/deprecated.md")
```

### Search Tools

**MemoryGlob** - Search by path pattern
```ruby
MemoryGlob(pattern: "skill/**")           # All skills
MemoryGlob(pattern: "concept/ruby/*")     # Ruby concepts
MemoryGlob(pattern: "fact/people/*.md")   # All people facts
```

**MemoryGrep** - Search by content pattern
```ruby
MemoryGrep(pattern: "authentication")
MemoryGrep(pattern: "api.*error", output_mode: "content")
MemoryGrep(pattern: "TODO", path: "concept/")              # Search only concepts
MemoryGrep(pattern: "endpoint", path: "fact/api-design")   # Search specific subdirectory
```

### Optimization Tools

**MemoryDefrag** - Analyze and optimize memory
```ruby
# Analyze health
MemoryDefrag(action: "analyze")

# Find duplicates
MemoryDefrag(action: "find_duplicates", similarity_threshold: 0.85)

# Find related entries (60-85% similarity)
MemoryDefrag(action: "find_related")

# Create bidirectional links
MemoryDefrag(action: "link_related", dry_run: false)

# Merge duplicates
MemoryDefrag(action: "merge_duplicates", dry_run: false)
```

### Skill Loading

**LoadSkill** - Load a skill and adapt tools
```ruby
LoadSkill(file_path: "skill/debugging/api-errors.md")
# - Swaps mutable tools to match skill requirements
# - Returns step-by-step instructions
# - Applies tool permissions from skill
```

---

## Semantic Search & Discovery

### Automatic Skill Discovery

**On EVERY user message**, SwarmMemory:

1. Extracts keywords from user prompt
2. Performs hybrid search (semantic + keyword)
3. Finds skills with ≥65% match
4. Injects system reminder with LoadSkill instructions

**Example:**

User: "Create a swarm using the Ruby DSL"

Agent sees:
```
<system-reminder>
🎯 Found 1 skill(s) in memory that may be relevant:

**Create a Swarm with SwarmSDK DSL** (78% match)
Path: `skill/ruby/create-swarm-dsl.md`
To use: `LoadSkill(file_path: "skill/ruby/create-swarm-dsl.md")`

**If a skill matches your task:** Load it to get step-by-step instructions.
</system-reminder>
```

### Dual Discovery

Searches **two categories in parallel**:

1. **Skills** (type="skill") - For loadable procedures
2. **Memories** (type="concept","fact","experience") - For context

**Result:** Both skills AND relevant background knowledge are suggested.

### Hybrid Scoring

Combines semantic similarity with keyword matching:

```
Query: "Create a swarm using Ruby DSL"
Skill Tags: ["swarmsdk", "ruby", "dsl", "swarm", "create"]

Semantic Score: 37.5% (embeddings)
Keyword Score:  100%  (5/5 tags match)
Hybrid Score:   (0.5 × 0.375) + (0.5 × 1.0) = 69% ✅ Above 65% threshold!
```

**Accuracy:** 78% average match for relevant skills (vs 43% with pure semantic)

---

## Storage Architecture

### Filesystem Adapter

SwarmMemory uses a **filesystem-based storage adapter** by default:

```
.swarm/assistant-memory/
├── concept/
│   └── ruby/
│       ├── classes.md               # Content
│       ├── classes.yml              # Metadata
│       └── classes.emb              # Embedding (binary)
├── skill/
│   └── debugging/
│       ├── api.md
│       ├── api.yml
│       └── api.emb
├── fact/
├── experience/
└── .lock                            # Cross-process lock file
```

**Hierarchical Storage:**
- Logical: `concept/ruby/classes.md`
- On Disk: `concept/ruby/classes.md`
- Storage matches logical paths exactly - no flattening
- Native directory structure for intuitive browsing
- Efficient glob operations with Dir.glob

**Three Files Per Entry:**
- `.md` - Markdown content
- `.yml` - Metadata (title, tags, type, etc.)
- `.emb` - Embedding vector (384-dim, binary)

### Embeddings

**Model:** `sentence-transformers/all-MiniLM-L6-v2` (via Informers)
- Size: ~90MB (unquantized), ~22MB (quantized)
- Dimensions: 384
- Speed: ~10-50ms per embedding
- Local: No API calls required

**What Gets Embedded:**
```
Title: Create a Swarm with SwarmSDK DSL
Tags: swarmsdk, ruby, dsl, swarm, agent, create
Domain: programming/ruby
Summary: This skill teaches you how to build swarms programmatically...
```

**NOT embedded:** Full content (optimized for search vs encyclopedic)

---

## Configuration

### Memory Block

```ruby
agent :assistant do
  memory do
    directory ".swarm/assistant-memory"  # Required
    # adapter :filesystem (optional, default)
  end
end
```

### What Happens

When memory is configured:

1. **Storage Created**: `FilesystemAdapter` + `InformersEmbedder`
2. **Tools Registered**: 8 memory tools + LoadSkill
3. **Prompt Injected**: Memory system guidance
4. **Discovery Enabled**: Semantic search on user messages
5. **Embeddings Generated**: For all stored content

---

## Relationship Discovery

### Find Related Entries

Discover semantically related entries:

```ruby
MemoryDefrag(action: "find_related")
```

**Output:**
```
# Related Entries (3 pairs)

## Pair 1: 72% similar
- memory://concept/ruby/classes.md (concept)
  "Ruby Classes"
- memory://concept/ruby/modules.md (concept)
  "Ruby Modules"

**Suggestion:** Add bidirectional links to cross-reference these related entries
```

### Auto-Link Related Entries

Create bidirectional cross-references:

```ruby
# Preview first
MemoryDefrag(action: "link_related", dry_run: true)

# Execute
MemoryDefrag(action: "link_related", dry_run: false)
```

**Result:** Updates `related` metadata arrays to cross-reference entries.

### CLI Shortcut

```bash
/defrag  # Runs find_related then link_related automatically
```

---

## Advanced Topics

### Custom Embeddings

Future: Swap embedding models

```ruby
# Not yet implemented - future API
memory do
  directory ".swarm/memory"
  embedder :informers, model: "bge-small-en-v1.5"
end
```

### Vector Database Adapters

Future: Use vector DB instead of filesystem

```ruby
# Not yet implemented - future API
memory do
  adapter :qdrant
  url "http://localhost:6333"
  collection "agent_memory"
end
```

**Plugin architecture makes this possible** - adapters just need to implement `Adapters::Base` interface.

---

## Best Practices

### Memory-First Protocol

**ALWAYS search memory before starting work:**

```ruby
# 1. Search for skills
MemoryGrep(pattern: "keyword1|keyword2|keyword3")

# 2. Load relevant skill if found
LoadSkill(file_path: "skill/domain/task.md")

# 3. THEN start working
```

### Comprehensive Tags

For skills especially, tags are your search index:

```ruby
# ❌ Bad: Minimal tags
tags: ["ruby", "debug"]

# ✅ Good: Comprehensive tags
tags: ["ruby", "debugging", "api", "errors", "http", "rest", "trace", "network", "troubleshooting"]
```

**Think:** "What would I search for in 6 months?"

### Knowledge Graph

Build relationships:

```ruby
# After creating multiple related entries
MemoryDefrag(action: "link_related", dry_run: false)

# Entries now cross-reference each other
MemoryRead(file_path: "concept/ruby/classes.md")
# metadata.related: ["memory://concept/ruby/modules.md", ...]
```

### Regular Maintenance

```ruby
# Every 15-20 entries
MemoryDefrag(action: "analyze")

# Every 50 entries
MemoryDefrag(action: "find_duplicates")
MemoryDefrag(action: "find_related")

# Every 100 entries
MemoryDefrag(action: "full", dry_run: true)
```

---

## Performance

### Semantic Search

- Query embedding: ~10-50ms
- Search 100 entries: ~10-100ms
- Total overhead: <150ms per user message

### Storage

- Write with embedding: ~50-100ms
- Read: <5ms (in-memory index)
- Glob/Grep: <50ms (filesystem scan)

### Limits

- **Max entry size:** 10MB per entry
- **Max total size:** 500MB per agent
- **Max entries:** ~5,000 entries (practical limit)

---

## Troubleshooting

### Embeddings Not Generated

**Symptom:** No `.emb` files, semantic search returns 0 results

**Cause:** Informers gem not installed or embedder not configured

**Fix:**
```bash
gem install informers
# Restart swarm - embeddings will be generated on next MemoryWrite
```

### Low Similarity Scores

**Symptom:** Skill has perfect tags but only 43% similarity

**Cause:** Using old embeddings (before improved embedding logic)

**Fix:**
```ruby
# Delete and recreate skill
MemoryDelete(file_path: "skill/old-skill.md")
# Then recreate with MemoryWrite - will use new embedding logic
```

### Memory Not Persisting

**Symptom:** Memory entries disappear after restart

**Cause:** Directory not configured or permissions issue

**Fix:**
```ruby
# Check directory in configuration
agent :name do
  memory do
    directory ".swarm/memory"  # Must be writable
  end
end
```

---

## See Also

- **Plugin System:** `docs/v2/guides/plugins.md` - How SwarmMemory integrates
- **Custom Adapters:** `docs/v2/guides/memory-adapters.md` - Build your own adapter
- **API Reference:** `docs/v2/reference/ruby-dsl.md#memory-configuration`
- **Changelog:** `docs/v2/CHANGELOG.swarm_memory.md`
