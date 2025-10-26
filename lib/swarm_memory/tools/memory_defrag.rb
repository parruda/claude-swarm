# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for analyzing and optimizing memory storage
    #
    # Provides defragmentation operations to maintain memory quality.
    # Each agent has its own isolated memory storage.
    class MemoryDefrag < RubyLLM::Tool
      description <<~DESC
        Analyze and optimize your memory storage for better precision, recall, and organization.

        THINK BEFORE CALLING: This tool has many actions and parameters. Choose the right action for your goal.

        **When to Run Defrag:**
        - Every 15-20 new memory entries created
        - Memory searches returning too many irrelevant results
        - Trouble finding specific information
        - Before major new tasks (check memory health)
        - Periodically as maintenance (every ~50 entries minimum)

        ## READ-ONLY ANALYSIS ACTIONS (Safe - No Changes)

        **1. analyze** - Get overall memory health report
        ```
        MemoryDefrag(action: "analyze")
        ```
        - Shows entry counts, quality scores, metadata coverage
        - Provides health score (0-100) - aim for 70+
        - ALWAYS run this first to understand memory state
        - No parameters needed

        **2. find_duplicates** - Identify similar/duplicate entries
        ```
        MemoryDefrag(action: "find_duplicates", similarity_threshold: 0.85)
        ```
        - Uses text and semantic similarity to find near-duplicates
        - similarity_threshold: 0.0-1.0 (default: 0.85) - higher = more strict
        - Start with 0.85, adjust based on results
        - Helps identify entries to merge

        **3. find_low_quality** - Find entries with poor metadata
        ```
        MemoryDefrag(action: "find_low_quality", confidence_filter: "low")
        ```
        - confidence_filter: 'low', 'medium', or 'high' (default: 'low')
        - Identifies entries missing metadata, tags, or with low confidence
        - Helps identify entries to improve or delete

        **4. find_archival_candidates** - Find old, unused entries
        ```
        MemoryDefrag(action: "find_archival_candidates", age_days: 90)
        ```
        - age_days: Threshold in days (default: 90)
        - Lists entries not updated in N days
        - Candidates for deletion or archival

        **5. find_related** - Discover entries that should be cross-linked
        ```
        MemoryDefrag(action: "find_related", min_similarity: 0.60, max_similarity: 0.85)
        ```
        - Finds pairs with 60-85% semantic similarity (related but not duplicates)
        - Shows current linking status (unlinked, one-way, bidirectional)
        - Suggests which links to create
        - Pure semantic similarity (no keyword boost) - finds content relationships

        ## ACTIVE OPTIMIZATION ACTIONS (Modify Memory)

        **IMPORTANT:** All active operations default to dry_run=true for safety. Set dry_run=false to actually perform changes.

        **6. link_related** - Create bidirectional links between related entries
        ```
        # Preview first
        MemoryDefrag(action: "link_related", min_similarity: 0.60, max_similarity: 0.85, dry_run: true)

        # Execute after reviewing
        MemoryDefrag(action: "link_related", min_similarity: 0.60, max_similarity: 0.85, dry_run: false)
        ```
        Parameters:
        - min_similarity: 0.0-1.0 (default: 0.60) - minimum relationship threshold
        - max_similarity: 0.0-1.0 (default: 0.85) - maximum (above = duplicates)
        - dry_run: true (preview) or false (execute)

        What it does:
        - Finds related but not duplicate entries (60-85% similarity)
        - Creates bidirectional links in 'related' metadata
        - Skips already-linked pairs
        - Builds your knowledge graph automatically

        **7. merge_duplicates** - Merge similar entries
        ```
        # Preview first (dry_run defaults to true)
        MemoryDefrag(action: "merge_duplicates", similarity_threshold: 0.85, dry_run: true)

        # Execute after reviewing preview
        MemoryDefrag(action: "merge_duplicates", similarity_threshold: 0.85, dry_run: false)
        ```
        Parameters:
        - similarity_threshold: 0.0-1.0 (default: 0.85) - matching threshold
        - merge_strategy: 'keep_newer', 'keep_larger', 'combine' (default: 'keep_newer')
        - dry_run: true (preview) or false (execute)

        What it does:
        - Merges similar entries to reduce duplication
        - Creates stub files with auto-redirect to merged entry
        - Preserves access to old paths via redirects

        **8. cleanup_stubs** - Remove old redirect stub files
        ```
        MemoryDefrag(action: "cleanup_stubs", age_days: 30, max_hits: 3, dry_run: false)
        ```
        Parameters:
        - age_days: Minimum age to delete (default: 90)
        - max_hits: Maximum access count to delete (default: 10)
        - dry_run: true (preview) or false (execute)

        What it does:
        - Deletes stub files that are old AND rarely accessed
        - Keeps frequently-accessed stubs even if old
        - Reduces clutter from obsolete redirects

        **9. compact** - Delete low-value entries
        ```
        MemoryDefrag(action: "compact", min_quality_score: 20, min_age_days: 30, max_hits: 0, dry_run: false)
        ```
        Parameters:
        - min_quality_score: Minimum quality threshold (default: 20)
        - min_age_days: Minimum age in days (default: 30)
        - max_hits: Maximum access count (default: 10)
        - dry_run: true (preview) or false (execute)

        What it does:
        - Permanently deletes entries matching ALL criteria
        - Targets low-quality, old, unused entries
        - Frees up memory space

        **10. full** - Complete optimization workflow
        ```
        # Preview full optimization
        MemoryDefrag(action: "full", dry_run: true)

        # Execute full optimization
        MemoryDefrag(action: "full", dry_run: false)
        ```
        What it does:
        - Runs: merge_duplicates → cleanup_stubs → compact
        - Shows health score improvement (before/after)
        - Most comprehensive optimization
        - ALWAYS preview first!
        - Does NOT include link_related (run separately if desired)

        ## BEST PRACTICES

        **1. Always Preview First:**
        - Use dry_run=true to see what would happen
        - Review the preview carefully
        - Only proceed if changes look correct

        **2. Start with Analysis:**
        ```
        # Step 1: Check health
        MemoryDefrag(action: "analyze")

        # Step 2: Find issues
        MemoryDefrag(action: "find_duplicates")
        MemoryDefrag(action: "find_low_quality")

        # Step 3: Preview fixes
        MemoryDefrag(action: "merge_duplicates", dry_run: true)

        # Step 4: Execute if preview looks good
        MemoryDefrag(action: "merge_duplicates", dry_run: false)

        # Step 5: Verify improvement
        MemoryDefrag(action: "analyze")
        ```

        **3. Conservative Thresholds:**
        - similarity_threshold: Start at 0.85 or higher
        - age_days: Start at 90+ days (don't delete recent entries)
        - min_quality_score: Start at 20 or lower (only worst entries)

        **4. Regular Maintenance Schedule:**
        - Light check: Every 15-20 new entries (just analyze)
        - Medium check: Every 50 entries (analyze + find_*)
        - Heavy maintenance: Every 100 entries (full optimization)

        **5. Safety Checklist:**
        - ✓ Preview with dry_run=true first
        - ✓ Review what will be changed
        - ✓ Use conservative thresholds initially
        - ✓ Re-analyze after to verify improvement
        - ✓ Don't delete recent or frequently-accessed entries

        ## PARAMETER REFERENCE

        All parameters are optional and have sensible defaults:

        - action: 'analyze', 'find_duplicates', 'find_low_quality', 'find_archival_candidates', 'find_related', 'link_related', 'merge_duplicates', 'cleanup_stubs', 'compact', 'full' (default: 'analyze')
        - dry_run: true (preview) or false (execute) - default: true for safety
        - similarity_threshold: 0.0-1.0 (default: 0.85) - for merge_duplicates
        - min_similarity: 0.0-1.0 (default: 0.60) - for find_related/link_related
        - max_similarity: 0.0-1.0 (default: 0.85) - for find_related/link_related
        - merge_strategy: 'keep_newer', 'keep_larger', 'combine' (default: 'keep_newer')
        - age_days: Days threshold (default: 90)
        - max_hits: Access count threshold (default: 10)
        - min_quality_score: Quality threshold (default: 20)
        - confidence_filter: 'low', 'medium', 'high' (default: 'low')
      DESC

      param :action,
        desc: "Action: 'analyze', 'find_duplicates', 'find_low_quality', 'find_archival_candidates', 'find_related', 'link_related', 'merge_duplicates', 'cleanup_stubs', 'compact', 'full' (default: 'analyze')",
        required: false

      param :dry_run,
        desc: "Preview mode - show what would be done without doing it (default: true for safety)",
        required: false

      param :similarity_threshold,
        desc: "Similarity threshold for duplicate detection 0.0-1.0 (default: 0.85)",
        required: false

      param :min_similarity,
        desc: "Minimum similarity for find_related/link_related 0.0-1.0 (default: 0.60)",
        required: false

      param :max_similarity,
        desc: "Maximum similarity for find_related/link_related 0.0-1.0 (default: 0.85)",
        required: false

      param :merge_strategy,
        desc: "Merge strategy: 'keep_newer', 'keep_larger', 'combine' (default: 'keep_newer')",
        required: false

      param :age_days,
        desc: "Age threshold for archival/cleanup in days (default: 90)",
        required: false

      param :max_hits,
        desc: "Maximum hits threshold for cleanup/archive (default: 10)",
        required: false

      param :min_quality_score,
        desc: "Minimum quality score for compact (default: 20)",
        required: false

      param :confidence_filter,
        desc: "Confidence level to filter: 'low', 'medium', 'high' (default: 'low')",
        required: false

      # Initialize with storage instance
      #
      # @param storage [Core::Storage] Storage instance
      def initialize(storage:)
        super()
        @storage = storage
        @defragmenter = nil # Lazy load
      end

      # Override name to return simple "MemoryDefrag"
      def name
        "MemoryDefrag"
      end

      # Execute the tool
      #
      # @param action [String] Action to perform
      # @param dry_run [Boolean] Preview mode (default: true)
      # @param similarity_threshold [Float] Duplicate detection threshold
      # @param min_similarity [Float] Minimum for relationship detection
      # @param max_similarity [Float] Maximum for relationship detection
      # @param merge_strategy [String] Merge strategy
      # @param age_days [Integer] Age threshold
      # @param max_hits [Integer] Maximum hits threshold
      # @param min_quality_score [Integer] Minimum quality score
      # @param confidence_filter [String] Confidence level filter
      # @return [String] Operation report
      def execute(
        action: "analyze",
        dry_run: true,
        similarity_threshold: 0.85,
        min_similarity: 0.60,
        max_similarity: 0.85,
        merge_strategy: "keep_newer",
        age_days: 90,
        max_hits: 10,
        min_quality_score: 20,
        confidence_filter: "low"
      )
        ensure_defragmenter_loaded

        case action.to_s.downcase
        # Read-only operations
        when "analyze"
          @defragmenter.health_report
        when "find_duplicates"
          @defragmenter.find_duplicates_report(threshold: similarity_threshold.to_f)
        when "find_low_quality"
          @defragmenter.find_low_quality_report(confidence_filter: confidence_filter.to_s.downcase)
        when "find_archival_candidates"
          @defragmenter.find_archival_candidates_report(age_days: age_days.to_i)
        when "find_related"
          @defragmenter.find_related_report(min_threshold: min_similarity.to_f, max_threshold: max_similarity.to_f)

        # Active operations (modify memory)
        when "link_related"
          @defragmenter.link_related_active(
            min_threshold: min_similarity.to_f,
            max_threshold: max_similarity.to_f,
            dry_run: dry_run,
          )
        when "merge_duplicates"
          @defragmenter.merge_duplicates_active(
            threshold: similarity_threshold.to_f,
            strategy: merge_strategy.to_sym,
            dry_run: dry_run,
          )
        when "cleanup_stubs"
          @defragmenter.cleanup_stubs_active(
            min_age_days: age_days.to_i,
            max_hits: max_hits.to_i,
            dry_run: dry_run,
          )
        when "compact"
          @defragmenter.compact_active(
            min_quality_score: min_quality_score.to_i,
            min_age_days: age_days.to_i,
            max_hits: max_hits.to_i,
            dry_run: dry_run,
          )
        when "full"
          # Full can be read-only analysis OR active optimization
          if dry_run
            # Just analysis
            @defragmenter.full_analysis(
              similarity_threshold: similarity_threshold.to_f,
              age_days: age_days.to_i,
              confidence_filter: confidence_filter.to_s.downcase,
            )
          else
            # Active optimization
            @defragmenter.full_optimization(dry_run: dry_run)
          end
        else
          validation_error("Invalid action: #{action}. Must be one of: analyze, find_duplicates, find_low_quality, find_archival_candidates, find_related, link_related, merge_duplicates, cleanup_stubs, compact, full")
        end
      rescue ArgumentError => e
        validation_error(e.message)
      rescue StandardError => e
        # Provide detailed error information
        error_msg = "Defrag error: #{e.class.name} - #{e.message}\n\n"
        error_msg += "Backtrace:\n"
        error_msg += e.backtrace.first(10).join("\n")
        validation_error(error_msg)
      end

      private

      def validation_error(message)
        "<tool_use_error>InputValidationError: #{message}</tool_use_error>"
      end

      # Lazy load defragmenter with embedder if available
      #
      # @return [void]
      def ensure_defragmenter_loaded
        return if @defragmenter

        # Don't load embedder automatically - it can be slow (model download)
        # Defrag works fine without embeddings (uses text similarity instead)
        embedder = nil

        @defragmenter = Optimization::Defragmenter.new(
          adapter: @storage.adapter,
          embedder: embedder,
        )
      rescue StandardError => e
        raise EmbeddingError, "Failed to initialize defragmenter: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end
  end
end
