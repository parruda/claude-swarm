# frozen_string_literal: true

module SwarmMemory
  module Tools
    # Tool for analyzing and optimizing memory storage
    #
    # Provides defragmentation operations to maintain memory quality.
    # Each agent has its own isolated memory storage.
    class MemoryDefrag < RubyLLM::Tool
      description <<~DESC
        Analyze and optimize your memory storage for better precision and recall.

        Operations:
        - analyze: Report memory health and statistics (read-only)
        - find_duplicates: Find similar entries (read-only report)
        - find_low_quality: Find entries with missing metadata (read-only report)
        - find_archival_candidates: Find old, unused entries (read-only report)
        - merge_duplicates: Actually merge duplicate entries (creates stubs)
        - cleanup_stubs: Remove old redirect files (deletes permanently)
        - compact: Delete low-value entries permanently (quality < 20, age > 30d, hits = 0)
        - full: Run all optimizations together

        SAFETY: Active operations (merge_duplicates, cleanup_stubs, compact, full) default to dry_run=true.
        Set dry_run=false to actually perform changes.
      DESC

      param :action,
        desc: "Action: 'analyze', 'find_duplicates', 'find_low_quality', 'find_archival_candidates', 'merge_duplicates', 'cleanup_stubs', 'compact', 'full' (default: 'analyze')",
        required: false

      param :dry_run,
        desc: "Preview mode - show what would be done without doing it (default: true for safety)",
        required: false

      param :similarity_threshold,
        desc: "Similarity threshold for duplicate detection 0.0-1.0 (default: 0.85)",
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

        # Active operations (modify memory)
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
          validation_error("Invalid action: #{action}. Must be one of: analyze, find_duplicates, find_low_quality, find_archival_candidates, merge_duplicates, cleanup_stubs, compact, full")
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
