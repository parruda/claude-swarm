# frozen_string_literal: true

module SwarmMemory
  module Optimization
    # Defragments memory by finding duplicates, low-quality entries, and archival candidates
    #
    # This class analyzes memory and suggests optimizations without making changes.
    # Agents must manually review and act on suggestions.
    class Defragmenter
      # Initialize defragmenter
      #
      # @param adapter [Adapters::Base] Storage adapter
      # @param embedder [Embeddings::Embedder, nil] Optional embedder for semantic duplicate detection
      def initialize(adapter:, embedder: nil)
        @adapter = adapter
        @embedder = embedder
        @analyzer = Analyzer.new(adapter: adapter)
      end

      # Generate health report
      #
      # @return [String] Formatted health report
      def health_report
        @analyzer.health_report
      end

      # Run full analysis (all operations)
      #
      # @param similarity_threshold [Float] Threshold for duplicate detection
      # @param age_days [Integer] Age threshold for archival
      # @param confidence_filter [String] Confidence level filter
      # @return [String] Complete analysis report
      def full_analysis(similarity_threshold: 0.85, age_days: 90, confidence_filter: "low")
        report = []
        report << "# Full Memory Defrag Analysis\n"
        report << @analyzer.health_report
        report << "\n---\n"
        report << find_duplicates_report(threshold: similarity_threshold)
        report << "\n---\n"
        report << find_low_quality_report(confidence_filter: confidence_filter)
        report << "\n---\n"
        report << find_archival_candidates_report(age_days: age_days)

        report.join("\n")
      end

      # Find potential duplicate entries
      #
      # Uses both text similarity (Jaccard) and semantic similarity (embeddings)
      # to find entries that could be merged.
      #
      # @param threshold [Float] Similarity threshold (0.0-1.0)
      # @return [Array<Hash>] Duplicate pairs with similarity scores
      def find_duplicates(threshold: 0.85)
        entries = @adapter.list
        return [] if entries.size < 2

        duplicates = []
        all_entries = @adapter.all_entries

        # Compare all pairs
        entry_paths = entries.map { |e| e[:path] }
        entry_paths.combination(2).each do |path1, path2|
          entry1 = all_entries[path1]
          entry2 = all_entries[path2]

          # Calculate text similarity (always available)
          text_sim = Search::TextSimilarity.jaccard(entry1.content, entry2.content)

          # Calculate semantic similarity if embeddings available
          semantic_sim = if entry1.embedded? && entry2.embedded?
            Search::TextSimilarity.cosine(entry1.embedding, entry2.embedding)
          end

          # Use highest similarity score
          similarity = [text_sim, semantic_sim].compact.max

          next if similarity < threshold

          duplicates << {
            path1: path1,
            path2: path2,
            similarity: (similarity * 100).round(1),
            text_similarity: (text_sim * 100).round(1),
            semantic_similarity: semantic_sim ? (semantic_sim * 100).round(1) : nil,
            title1: entry1.title,
            title2: entry2.title,
            size1: entry1.size,
            size2: entry2.size,
          }
        end

        duplicates.sort_by { |d| -d[:similarity] }
      end

      # Find low-quality entries
      #
      # @param confidence_filter [String] Filter level ("low", "medium", "high")
      # @return [Array<Hash>] Low-quality entries with issues
      def find_low_quality(confidence_filter: "low")
        entries = @adapter.list
        low_quality = []

        entries.each do |entry_info|
          entry = @adapter.read_entry(file_path: entry_info[:path])

          # Get metadata from entry (always has string keys from .yml file)
          metadata = entry.metadata || {}

          # Calculate quality score from metadata
          quality = calculate_quality_from_metadata(metadata)

          # Check for issues (all keys are strings)
          issues = []
          issues << "No metadata" if metadata.empty?
          issues << "Confidence: #{metadata["confidence"]}" if should_flag_confidence?(metadata["confidence"], confidence_filter)
          issues << "No type specified" if metadata["type"].nil?
          issues << "No tags" if (metadata["tags"] || []).empty?
          issues << "No related links" if (metadata["related"] || []).empty?
          issues << "Not embedded" if !entry.embedded? && @embedder

          next if issues.empty?

          low_quality << {
            path: entry_info[:path],
            title: entry.title,
            issues: issues,
            confidence: metadata["confidence"] || "unknown",
            quality_score: quality,
          }
        end

        low_quality.sort_by { |e| e[:quality_score] }
      end

      # Find entries that could be archived (old and unused)
      #
      # @param age_days [Integer] Minimum age in days
      # @return [Array<Hash>] Archival candidates
      def find_archival_candidates(age_days: 90)
        entries = @adapter.list
        cutoff_date = Time.now - (age_days * 24 * 60 * 60)

        candidates = entries.select do |entry_info|
          entry_info[:updated_at] < cutoff_date
        end

        candidates.map do |entry_info|
          entry = @adapter.read_entry(file_path: entry_info[:path])
          metadata = entry.metadata || {}

          {
            path: entry_info[:path],
            title: entry.title,
            age_days: ((Time.now - entry_info[:updated_at]) / 86400).round,
            last_verified: metadata["last_verified"],
            confidence: metadata["confidence"] || "unknown",
            size: entry.size,
          }
        end.sort_by { |e| -e[:age_days] }
      end

      # Generate formatted report for duplicates
      #
      # @param threshold [Float] Similarity threshold
      # @return [String] Formatted report
      def find_duplicates_report(threshold: 0.85)
        duplicates = find_duplicates(threshold: threshold)

        return "No duplicate entries found above #{(threshold * 100).round}% similarity." if duplicates.empty?

        report = []
        report << "# Potential Duplicates (#{duplicates.size} pairs)"
        report << ""
        report << "Found #{duplicates.size} pair(s) of similar entries that could potentially be merged."
        report << ""

        duplicates.each_with_index do |dup, index|
          report << "## Pair #{index + 1}: #{dup[:similarity]}% similar"
          report << "- memory://#{dup[:path1]}"
          report << "  Title: \"#{dup[:title1]}\""
          report << "  Size: #{format_bytes(dup[:size1])}"
          report << "- memory://#{dup[:path2]}"
          report << "  Title: \"#{dup[:title2]}\""
          report << "  Size: #{format_bytes(dup[:size2])}"
          report << ""
          report << "  Text similarity: #{dup[:text_similarity]}%"
          report << if dup[:semantic_similarity]
            "  Semantic similarity: #{dup[:semantic_similarity]}%"
          else
            "  Semantic similarity: N/A (no embeddings)"
          end
          report << ""
          report << "  **Suggestion:** Review both entries and consider merging with MemoryMultiEdit"
          report << ""
        end

        report.join("\n")
      end

      # Generate formatted report for low-quality entries
      #
      # @param confidence_filter [String] Confidence level filter
      # @return [String] Formatted report
      def find_low_quality_report(confidence_filter: "low")
        entries = find_low_quality(confidence_filter: confidence_filter)

        return "No low-quality entries found." if entries.empty?

        report = []
        report << "# Low-Quality Entries (#{entries.size} entries)"
        report << ""
        report << "Found #{entries.size} entry/entries with quality issues."
        report << ""

        entries.each do |entry|
          report << "## memory://#{entry[:path]}"
          report << "- Title: #{entry[:title]}"
          report << "- Quality score: #{entry[:quality_score]}/100"
          report << "- Confidence: #{entry[:confidence]}"
          report << "- Issues:"
          entry[:issues].each do |issue|
            report << "  - #{issue}"
          end
          report << ""
          report << "  **Suggestion:** Add proper frontmatter and metadata with MemoryEdit"
          report << ""
        end

        report.join("\n")
      end

      # Generate formatted report for archival candidates
      #
      # @param age_days [Integer] Age threshold
      # @return [String] Formatted report
      def find_archival_candidates_report(age_days: 90)
        candidates = find_archival_candidates(age_days: age_days)

        return "No entries older than #{age_days} days found." if candidates.empty?

        report = []
        report << "# Archival Candidates (#{candidates.size} entries older than #{age_days} days)"
        report << ""
        report << "Found #{candidates.size} old entry/entries that could be archived."
        report << ""

        candidates.each do |entry|
          report << "## memory://#{entry[:path]}"
          report << "- Title: #{entry[:title]}"
          report << "- Age: #{entry[:age_days]} days"
          report << "- Last verified: #{entry[:last_verified] || "never"}"
          report << "- Confidence: #{entry[:confidence]}"
          report << "- Size: #{format_bytes(entry[:size])}"
          report << ""
          report << "  **Suggestion:** Review and delete with MemoryDelete if truly obsolete, or use compact action with appropriate thresholds"
          report << ""
        end

        report.join("\n")
      end

      # Find related entries that should be cross-linked
      #
      # Finds entry pairs with semantic similarity in the "related" range
      # but NOT duplicates. Uses pure semantic similarity (no keyword boost).
      #
      # @param min_threshold [Float] Minimum similarity for relationships (default: 0.60)
      # @param max_threshold [Float] Maximum similarity (above = duplicates) (default: 0.85)
      # @return [Array<Hash>] Related pairs
      def find_related(min_threshold: 0.60, max_threshold: 0.85)
        entries = @adapter.list
        return [] if entries.size < 2

        related_pairs = []
        all_entries = @adapter.all_entries

        # Compare all pairs
        entry_paths = entries.map { |e| e[:path] }
        entry_paths.combination(2).each do |path1, path2|
          entry1 = all_entries[path1]
          entry2 = all_entries[path2]

          # Skip if no embeddings (need semantic similarity)
          next unless entry1.embedded? && entry2.embedded?

          # Calculate PURE semantic similarity (no keyword boosting for merging)
          semantic_sim = Search::TextSimilarity.cosine(entry1.embedding, entry2.embedding)

          # Must be in the "related" range
          next if semantic_sim < min_threshold
          next if semantic_sim >= max_threshold

          # Check current linking status
          entry1_related = (entry1.metadata["related"] || []).map { |r| r.sub(%r{^memory://}, "") }
          entry2_related = (entry2.metadata["related"] || []).map { |r| r.sub(%r{^memory://}, "") }

          linked_1_to_2 = entry1_related.include?(path2)
          linked_2_to_1 = entry2_related.include?(path1)
          already_linked = linked_1_to_2 && linked_2_to_1

          # Extract metadata
          type1 = entry1.metadata["type"] || "unknown"
          type2 = entry2.metadata["type"] || "unknown"

          related_pairs << {
            path1: path1,
            path2: path2,
            similarity: (semantic_sim * 100).round(1),
            title1: entry1.title,
            title2: entry2.title,
            type1: type1,
            type2: type2,
            already_linked: already_linked,
            linked_1_to_2: linked_1_to_2,
            linked_2_to_1: linked_2_to_1,
          }
        end

        related_pairs.sort_by { |d| -d[:similarity] }
      end

      # Generate formatted report for related entries
      #
      # @param min_threshold [Float] Minimum similarity
      # @param max_threshold [Float] Maximum similarity
      # @return [String] Formatted report
      def find_related_report(min_threshold: 0.60, max_threshold: 0.85)
        pairs = find_related(min_threshold: min_threshold, max_threshold: max_threshold)

        return "No related entry pairs found in #{(min_threshold * 100).round}-#{(max_threshold * 100).round}% similarity range." if pairs.empty?

        report = []
        report << "# Related Entries (#{pairs.size} pairs)"
        report << ""
        report << "Found #{pairs.size} pair(s) of semantically related entries."
        report << "Similarity range: #{(min_threshold * 100).round}-#{(max_threshold * 100).round}% (pure semantic, no keyword boost)"
        report << ""

        pairs.each_with_index do |pair, index|
          report << "## Pair #{index + 1}: #{pair[:similarity]}% similar"
          report << "- memory://#{pair[:path1]} (#{pair[:type1]})"
          report << "  \"#{pair[:title1]}\""
          report << "- memory://#{pair[:path2]} (#{pair[:type2]})"
          report << "  \"#{pair[:title2]}\""
          report << ""

          if pair[:already_linked]
            report << "  ✓ Already linked bidirectionally"
          elsif pair[:linked_1_to_2]
            report << "  → Entry 1 links to Entry 2, but not vice versa"
            report << "  **Suggestion:** Add backward link from Entry 2 to Entry 1"
          elsif pair[:linked_2_to_1]
            report << "  → Entry 2 links to Entry 1, but not vice versa"
            report << "  **Suggestion:** Add backward link from Entry 1 to Entry 2"
          else
            report << "  **Suggestion:** Add bidirectional links to cross-reference these related entries"
          end
          report << ""
        end

        report << "To automatically create missing links, use:"
        report << "  MemoryDefrag(action: \"link_related\", dry_run: true)  # Preview first"
        report << "  MemoryDefrag(action: \"link_related\", dry_run: false) # Execute"
        report << ""

        report.join("\n")
      end

      # ============================================================================
      # ACTIVE OPTIMIZATION OPERATIONS (Actually modify memory)
      # ============================================================================

      # Merge duplicate entries
      #
      # @param threshold [Float] Similarity threshold
      # @param strategy [Symbol] Merge strategy (:keep_newer, :keep_larger, :combine)
      # @param dry_run [Boolean] If true, show what would be done without doing it
      # @return [String] Result report
      def merge_duplicates_active(threshold: 0.85, strategy: :keep_newer, dry_run: true)
        duplicates = find_duplicates(threshold: threshold)

        return "No duplicates found above #{(threshold * 100).round}% similarity." if duplicates.empty?

        results = []
        freed_bytes = 0

        duplicates.each do |pair|
          if dry_run
            results << "Would merge: #{pair[:path2]} → #{pair[:path1]} (#{pair[:similarity]}% similar)"
          else
            # Actually merge
            result_info = merge_pair(pair, strategy: strategy)
            freed_bytes += result_info[:freed_bytes]
            results << "✓ Merged: #{result_info[:merged_path]} → #{result_info[:kept_path]}"
          end
        end

        format_merge_report(results, duplicates.size, freed_bytes, dry_run)
      end

      # Clean up old stub files
      #
      # @param min_age_days [Integer] Minimum age for cleanup
      # @param max_hits [Integer] Maximum hits to consider for cleanup
      # @param dry_run [Boolean] Preview mode
      # @return [String] Result report
      def cleanup_stubs_active(min_age_days: 30, max_hits: 3, dry_run: true)
        stubs = find_stubs_to_cleanup(min_age_days: min_age_days, max_hits: max_hits)

        return "No stubs found for cleanup." if stubs.empty?

        results = []
        freed_bytes = 0

        stubs.each do |stub|
          if dry_run
            results << "Would delete stub: #{stub[:path]} (age: #{stub[:age_days]}d, hits: #{stub[:hits]})"
          else
            freed_bytes += stub[:size]
            @adapter.delete(file_path: stub[:path])
            results << "✓ Deleted stub: #{stub[:path]}"
          end
        end

        format_cleanup_report(results, stubs.size, freed_bytes, dry_run)
      end

      # Compact low-value entries (delete permanently)
      #
      # @param min_quality_score [Integer] Minimum quality threshold (0-100)
      # @param min_age_days [Integer] Minimum age
      # @param max_hits [Integer] Maximum hits
      # @param dry_run [Boolean] Preview mode
      # @return [String] Result report
      def compact_active(min_quality_score: 20, min_age_days: 30, max_hits: 0, dry_run: true)
        entries = @adapter.list
        low_value = []

        entries.each do |entry_info|
          entry = @adapter.read_entry(file_path: entry_info[:path])

          # Calculate quality from metadata (not content)
          quality = calculate_quality_from_metadata(entry.metadata || {})

          age_days = ((Time.now - entry.updated_at) / 86400).round
          hits = entry.metadata&.dig("hits") || 0

          next if quality >= min_quality_score || age_days < min_age_days || hits > max_hits

          low_value << {
            path: entry_info[:path],
            quality: quality,
            age_days: age_days,
            hits: hits,
            size: entry.size,
          }
        end

        return "No low-value entries found for compaction." if low_value.empty?

        results = []
        freed_bytes = 0

        low_value.each do |entry|
          if dry_run
            results << "Would delete: #{entry[:path]} (quality: #{entry[:quality]}, age: #{entry[:age_days]}d, hits: #{entry[:hits]})"
          else
            freed_bytes += entry[:size]
            @adapter.delete(file_path: entry[:path])
            results << "✓ Deleted: #{entry[:path]}"
          end
        end

        format_compact_report(results, low_value.size, freed_bytes, dry_run)
      end

      # Create bidirectional links between related entries
      #
      # Finds related pairs and updates their 'related' metadata to cross-reference each other.
      #
      # @param min_threshold [Float] Minimum similarity (default: 0.60)
      # @param max_threshold [Float] Maximum similarity (default: 0.85)
      # @param dry_run [Boolean] Preview mode (default: true)
      # @return [String] Result report
      def link_related_active(min_threshold: 0.60, max_threshold: 0.85, dry_run: true)
        pairs = find_related(min_threshold: min_threshold, max_threshold: max_threshold)

        # Filter to only pairs that need linking
        needs_linking = pairs.reject { |p| p[:already_linked] }

        if needs_linking.empty?
          return "No related entries found that need linking. All similar entries are already cross-referenced."
        end

        report = []
        report << (dry_run ? "# Link Related Entries (DRY RUN)" : "# Link Related Entries")
        report << ""
        report << "Found #{needs_linking.size} pair(s) that should be cross-linked."
        report << ""

        links_created = 0

        needs_linking.each_with_index do |pair, index|
          report << "## Pair #{index + 1}: #{pair[:similarity]}% similar"
          report << "- memory://#{pair[:path1]}"
          report << "- memory://#{pair[:path2]}"
          report << ""

          if dry_run
            # Show what would happen
            if !pair[:linked_1_to_2] && !pair[:linked_2_to_1]
              report << "  Would add bidirectional links:"
              report << "    - Add #{pair[:path2]} to #{pair[:path1]}'s related array"
              report << "    - Add #{pair[:path1]} to #{pair[:path2]}'s related array"
            elsif !pair[:linked_1_to_2]
              report << "  Would add backward link:"
              report << "    - Add #{pair[:path2]} to #{pair[:path1]}'s related array"
            elsif !pair[:linked_2_to_1]
              report << "  Would add backward link:"
              report << "    - Add #{pair[:path1]} to #{pair[:path2]}'s related array"
            end
          else
            # Actually create links
            created = create_bidirectional_links(pair[:path1], pair[:path2], pair[:linked_1_to_2], pair[:linked_2_to_1])
            links_created += created

            report << "  ✓ Created #{created} link(s)"
          end
          report << ""
        end

        report << if dry_run
          "**DRY RUN:** No changes made. Set dry_run=false to execute."
        else
          "**COMPLETED:** Created #{links_created} link(s) across #{needs_linking.size} pairs."
        end

        report.join("\n")
      end

      # Full optimization (all operations)
      #
      # @param dry_run [Boolean] Preview mode (default: true)
      # @return [String] Complete optimization report
      def full_optimization(dry_run: true)
        report = []
        report << "# Full Memory Optimization"
        report << ""
        mode_message = dry_run ? "## DRY RUN MODE - No changes will be made" : "## ACTIVE MODE - Performing optimizations"
        report << mode_message
        report << ""

        # 1. Health baseline
        initial_health = @analyzer.analyze
        report << "Initial health score: #{initial_health[:health_score]}/100"
        report << ""

        # 2. Merge duplicates
        report << "## 1. Merging Duplicates"
        report << merge_duplicates_active(dry_run: dry_run)
        report << ""

        # 3. Cleanup stubs
        report << "## 2. Cleaning Up Stubs"
        report << cleanup_stubs_active(dry_run: dry_run)
        report << ""

        # 4. Compact low-value
        report << "## 3. Compacting Low-Value Entries"
        report << compact_active(dry_run: dry_run)
        report << ""

        # 6. Final health check
        unless dry_run
          final_health = @analyzer.analyze
          report << "## Summary"
          report << "Health score: #{initial_health[:health_score]} → #{final_health[:health_score]} (+#{final_health[:health_score] - initial_health[:health_score]})"
        end

        report.join("\n")
      end

      private

      def should_flag_confidence?(confidence, filter_level)
        return false if confidence.nil?

        levels = { "low" => 0, "medium" => 1, "high" => 2 }
        filter_rank = levels[filter_level] || 0
        entry_rank = levels[confidence] || 0

        entry_rank <= filter_rank
      end

      def format_bytes(bytes)
        if bytes >= 1_000_000
          "#{(bytes.to_f / 1_000_000).round(1)}MB"
        elsif bytes >= 1_000
          "#{(bytes.to_f / 1_000).round(1)}KB"
        else
          "#{bytes}B"
        end
      end

      # Calculate quality score from metadata (not from content parsing)
      #
      # @param metadata [Hash] Metadata hash (string keys guaranteed)
      # @return [Integer] Quality score 0-100
      def calculate_quality_from_metadata(metadata)
        return 0 if metadata.nil? || metadata.empty?

        score = 0

        # All keys are strings (no defensive checks needed)
        score += 20 if metadata["type"]
        score += 20 if metadata["confidence"]
        score += 15 unless (metadata["tags"] || []).empty?
        score += 15 unless (metadata["related"] || []).empty?
        score += 10 if metadata["domain"]
        score += 10 if metadata["last_verified"]
        score += 10 if metadata["confidence"] == "high"

        score
      end

      # ============================================================================
      # HELPER METHODS FOR ACTIVE OPERATIONS
      # ============================================================================

      # Create bidirectional links between two entries
      #
      # Updates the 'related' metadata arrays to cross-reference entries.
      #
      # @param path1 [String] First entry path
      # @param path2 [String] Second entry path
      # @param already_linked_1_to_2 [Boolean] If entry1 already links to entry2
      # @param already_linked_2_to_1 [Boolean] If entry2 already links to entry1
      # @return [Integer] Number of links created (0-2)
      def create_bidirectional_links(path1, path2, already_linked_1_to_2, already_linked_2_to_1)
        links_created = 0
        all_entries = @adapter.all_entries

        # Add path2 to entry1's related array (if not already there)
        unless already_linked_1_to_2
          entry1 = all_entries[path1]
          related_array = entry1.metadata["related"] || []
          related_array << "memory://#{path2}"

          # Update entry1
          metadata = entry1.metadata.dup
          metadata["related"] = related_array.uniq

          @adapter.write(
            file_path: path1,
            content: entry1.content,
            title: entry1.title,
            embedding: entry1.embedding,
            metadata: metadata,
          )

          links_created += 1
        end

        # Add path1 to entry2's related array (if not already there)
        unless already_linked_2_to_1
          entry2 = all_entries[path2]
          related_array = entry2.metadata["related"] || []
          related_array << "memory://#{path1}"

          # Update entry2
          metadata = entry2.metadata.dup
          metadata["related"] = related_array.uniq

          @adapter.write(
            file_path: path2,
            content: entry2.content,
            title: entry2.title,
            embedding: entry2.embedding,
            metadata: metadata,
          )

          links_created += 1
        end

        links_created
      end

      # Merge a pair of duplicate entries
      #
      # @param pair [Hash] Duplicate pair info
      # @param strategy [Symbol] Merge strategy
      # @return [Hash] Result info with :kept_path, :merged_path, :freed_bytes
      def merge_pair(pair, strategy:)
        entry1 = @adapter.read_entry(file_path: pair[:path1])
        entry2 = @adapter.read_entry(file_path: pair[:path2])

        # Decide which to keep and which to merge
        keep_path, merge_path, keep_entry, merge_entry = case strategy
        when :keep_newer
          if entry1.updated_at > entry2.updated_at
            [pair[:path1], pair[:path2], entry1, entry2]
          else
            [pair[:path2], pair[:path1], entry2, entry1]
          end
        when :keep_larger
          if entry1.size > entry2.size
            [pair[:path1], pair[:path2], entry1, entry2]
          else
            [pair[:path2], pair[:path1], entry2, entry1]
          end
        when :combine
          # Keep path1, merge content from path2
          [pair[:path1], pair[:path2], entry1, entry2]
        else
          [pair[:path1], pair[:path2], entry1, entry2]
        end

        # Merge content if combining
        if strategy == :combine
          merged_content = combine_contents(keep_entry.content, merge_entry.content)
          merged_metadata = combine_metadata(keep_entry.metadata, merge_entry.metadata)

          @adapter.write(
            file_path: keep_path,
            content: merged_content,
            title: keep_entry.title,
            embedding: keep_entry.embedding,
            metadata: merged_metadata,
          )
        end

        # Create stub at merged location
        create_stub(from: merge_path, to: keep_path, reason: "merged")

        # Return result info
        {
          kept_path: keep_path,
          merged_path: merge_path,
          freed_bytes: merge_entry.size,
        }
      end

      # Create a stub (redirect) file
      #
      # @param from [String] Original path
      # @param to [String] Target path
      # @param reason [String] Reason (merged, moved)
      # @return [void]
      def create_stub(from:, to:, reason:)
        stub_content = "# #{reason} → #{to}\n\nThis entry was #{reason} into #{to}."

        @adapter.write(
          file_path: from,
          content: stub_content,
          title: "[STUB] → #{to}",
          metadata: { "stub" => true, "redirect_to" => to, "reason" => reason },
        )
      end

      # Find stubs that can be cleaned up
      #
      # @param min_age_days [Integer] Minimum age
      # @param max_hits [Integer] Maximum hits
      # @return [Array<Hash>] Stub info
      def find_stubs_to_cleanup(min_age_days:, max_hits:)
        stubs = []
        Time.now

        @adapter.list.each do |entry_info|
          entry = @adapter.read_entry(file_path: entry_info[:path])

          # Check if it's a stub
          next unless entry.content.start_with?("# merged →", "# moved →")

          age_days = ((Time.now - entry.updated_at) / 86400).round
          hits = entry.metadata&.dig("hits") || 0

          next if age_days < min_age_days || hits > max_hits

          stubs << {
            path: entry_info[:path],
            age_days: age_days,
            hits: hits,
            size: entry.size,
          }
        end

        stubs
      end

      # Combine contents from two entries
      #
      # @param content1 [String] First content
      # @param content2 [String] Second content
      # @return [String] Combined content
      def combine_contents(content1, content2)
        # Simple concatenation with separator
        # TODO: Could be smarter (LLM-based merge)
        "#{content1}\n\n---\n\n#{content2}"
      end

      # Combine metadata from two entries
      #
      # @param metadata1 [Hash] First metadata
      # @param metadata2 [Hash] Second metadata
      # @return [Hash] Combined metadata
      def combine_metadata(metadata1, metadata2)
        return metadata2 if metadata1.nil?
        return metadata1 if metadata2.nil?

        # Merge tags and related links
        combined = metadata1.dup
        combined["tags"] = ((metadata1["tags"] || []) + (metadata2["tags"] || [])).uniq
        combined["related"] = ((metadata1["related"] || []) + (metadata2["related"] || [])).uniq

        combined
      end

      # Format merge operation report
      #
      # @param results [Array<String>] Result messages
      # @param count [Integer] Number of merges
      # @param freed_bytes [Integer] Bytes freed
      # @param dry_run [Boolean] Dry run mode
      # @return [String] Formatted report
      def format_merge_report(results, count, freed_bytes, dry_run)
        report = []
        header = dry_run ? "Found #{count} duplicate pair(s) to merge:" : "Merged #{count} duplicate pair(s):"
        report << header
        report << ""
        results.each { |r| report << r }
        report << ""
        report << "Space freed: #{format_bytes(freed_bytes)}" unless dry_run
        report.join("\n")
      end

      # Format cleanup report
      def format_cleanup_report(results, count, freed_bytes, dry_run)
        report = []
        header = dry_run ? "Found #{count} stub(s) to clean up:" : "Cleaned up #{count} stub(s):"
        report << header
        report << ""
        results.each { |r| report << r }
        report << ""
        report << "Space freed: #{format_bytes(freed_bytes)}" unless dry_run
        report.join("\n")
      end

      # Format compact report
      def format_compact_report(results, count, freed_bytes, dry_run)
        report = []
        header = dry_run ? "Found #{count} low-value entry/entries to delete:" : "Deleted #{count} low-value entry/entries:"
        report << header
        report << ""
        results.each { |r| report << r }
        report << ""
        report << "Space freed: #{format_bytes(freed_bytes)}" unless dry_run
        report.join("\n")
      end
    end
  end
end
