# Changelog

All notable changes to SwarmMemory will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Plugin System Integration** - SwarmMemory integrates with SwarmSDK via plugin architecture
  - `SwarmMemory::Integration::SDKPlugin` implements SwarmSDK::Plugin interface
  - Auto-registers with SwarmSDK when loaded
  - Provides tools, storage, and system prompt contributions
  - Zero coupling: SwarmSDK works standalone without SwarmMemory

- **Semantic Search** - Hybrid search combining semantic similarity and keyword matching
  - **SemanticIndex** - Adapter-agnostic semantic search abstraction
  - **Hybrid Scoring**: 50% semantic similarity + 50% keyword tag matching
  - Improved recall accuracy from 43% → 78% for skill discovery
  - Works with any storage adapter (filesystem, future vector DBs)
  - `FilesystemAdapter.semantic_search()` with cosine similarity

- **Improved Embeddings** - Better semantic matching
  - Embeds title + tags + first paragraph (not full content)
  - Optimized for search queries vs encyclopedic content
  - Dramatically improved similarity scores for skill discovery
  - Uses Informers gem for fast local ONNX embeddings

- **Dual Discovery System** - Automatic skill and knowledge discovery
  - **Skill Discovery**: Searches skills on every user message
  - **Memory Discovery**: Searches concepts/facts/experiences in parallel
  - System reminders injected when high-confidence matches found (≥65%)
  - Shows path, title, match percentage for each result
  - LoadSkill instructions for skills, MemoryRead suggestions for memories

- **Relationship Discovery** - Automatic knowledge graph building
  - **`find_related` action**: Discover entries with 60-85% semantic similarity
  - **`link_related` action**: Create bidirectional links automatically
  - Pure semantic similarity (no keyword boost) for relationship detection
  - Skips already-linked pairs
  - Builds cross-referenced knowledge graph
  - Dry-run mode for preview before execution

- **Tool Description Enhancements** - Comprehensive, self-documenting tools
  - All 8 memory tools have detailed descriptions with examples
  - Explicit "REQUIRED: Provide ALL X parameters" statements
  - Path structure enforcement (4 fixed categories only)
  - Usage examples, common mistakes, best practices
  - Moved details from 845-line prompt to tool descriptions

- **Memory Prompt Optimization** - Drastically simplified
  - Reduced from 845 lines → 88 lines (90% reduction!)
  - Focuses on high-level concepts only
  - Details moved to tool descriptions
  - Memory-first protocol prominently placed
  - Enforces 4 fixed categories (concept/, fact/, skill/, experience/)

- **Logging & Observability**
  - `semantic_skill_search` - Logs skill discovery results
  - `semantic_memory_search` - Logs memory discovery results
  - `memory_embedding_generated` - Logs searchable text being embedded
  - Shows hybrid scores (semantic + keyword breakdown)
  - Includes debug info (top results, tags, similarity scores)

### Changed

- **Storage Architecture** - Now creates embeddings by default
  - `Storage.new(adapter:, embedder:)` with InformersEmbedder
  - Exposes `storage.semantic_index` for semantic search
  - `build_searchable_text()` creates optimized embedding input
  - `extract_first_paragraph()` for content summarization

- **FilesystemAdapter** - Enhanced with semantic search
  - Added `semantic_search(embedding:, top_k:, threshold:)` method
  - Added `cosine_similarity()` calculation
  - Returns results with similarity scores and metadata
  - Uses in-memory index for fast lookups

- **Tool Parameter Handling** - Flexible input formats
  - MemoryWrite accepts both JSON strings (from LLMs) and Ruby arrays/hashes (from tests)
  - `parse_array_param()` and `parse_object_param()` helpers
  - Backward compatible with test suite

- **Memory Categories Enforcement** - Strict validation
  - All tools enforce 4 fixed categories in descriptions
  - All examples use only valid paths
  - INVALID examples listed to prevent creation
  - Path validation in parameter descriptions

### Removed

- **Old Registration System** - Replaced by plugin
  - `Tools::Registry.register_extension()` calls removed
  - Now uses `SwarmSDK::PluginRegistry.register()`

### Breaking Changes

⚠️ **Major breaking changes:**

1. **Plugin-based integration required**
   - SwarmMemory MUST be loaded after SwarmSDK
   - Auto-registration happens on require
   - No manual registration needed

2. **Embeddings enabled by default**
   - Storage now creates embeddings for all entries
   - Requires Informers gem for semantic search
   - `.emb` files created alongside `.md` and `.yml` files

3. **Memory prompt location changed**
   - **Was**: Hardcoded path in SwarmSDK
   - **Now**: Plugin provides prompt via `system_prompt_contribution()`

## [2.0.0] - 2025-10-17

Initial release of SwarmMemory as separate gem.

See SwarmSDK CHANGELOG for prior memory system history (was part of SwarmSDK).
