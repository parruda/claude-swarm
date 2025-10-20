# frozen_string_literal: true

module SwarmMemory
  module Optimization
    # Analyzes memory health and generates statistics
    #
    # Provides insights about memory state, quality, and organization.
    class Analyzer
      # Initialize analyzer
      #
      # @param adapter [Adapters::Base] Storage adapter
      def initialize(adapter:)
        @adapter = adapter
      end

      # Analyze overall memory health
      #
      # @return [Hash] Comprehensive statistics and health metrics
      #
      # @example
      #   stats = analyzer.analyze
      #   stats[:health_score] # => 75
      #   stats[:total_entries] # => 42
      def analyze
        # List entries (handle errors gracefully)
        entries = @adapter.list
        return empty_analysis if entries.empty?

        stats = {
          total_entries: entries.size,
          total_size: @adapter.total_size,
          by_type: Hash.new(0),
          by_confidence: Hash.new(0),
          with_frontmatter: 0,
          with_embeddings: 0,
          with_tags: 0,
          with_links: 0,
          quality_scores: [],
        }

        # Analyze each entry
        entries.each do |entry_info|
          analyze_entry(entry_info[:path], stats)
        end

        # Calculate averages
        stats[:average_quality] = if stats[:quality_scores].empty?
          0
        else
          stats[:quality_scores].sum / stats[:quality_scores].size
        end

        # Calculate health score
        stats[:health_score] = calculate_health_score(stats)

        stats.except(:quality_scores) # Remove internal array
      end

      # Generate formatted health report
      #
      # @return [String] Human-readable health report
      def health_report
        stats = analyze
        format_health_report(stats)
      end

      private

      def empty_analysis
        {
          total_entries: 0,
          total_size: 0,
          by_type: {},
          by_confidence: {},
          with_frontmatter: 0,
          with_embeddings: 0,
          with_tags: 0,
          with_links: 0,
          average_quality: 0,
          health_score: 0,
          message: "Memory is empty. No entries to analyze.",
        }
      end

      def analyze_entry(path, stats)
        entry = @adapter.read_entry(file_path: path)

        # Get metadata from entry (always has string keys from .yml file)
        metadata = entry.metadata || {}

        # All keys are strings (guaranteed by FilesystemAdapter stringification)
        type = metadata["type"]
        confidence = metadata["confidence"]
        tags = metadata["tags"] || []
        related = metadata["related"] || []

        # Count by type
        if type
          stats[:by_type][type] += 1
          stats[:with_frontmatter] += 1 # Has metadata
        end

        # Count by confidence
        stats[:by_confidence][confidence] += 1 if confidence

        # Count embeddings
        stats[:with_embeddings] += 1 if entry.embedded?

        # Count tags and links
        stats[:with_tags] += 1 unless tags.empty?
        stats[:with_links] += 1 unless related.empty?

        # Track quality scores (calculate from metadata, not content)
        quality = calculate_quality_from_metadata(metadata)
        stats[:quality_scores] << quality
      end

      def calculate_health_score(stats)
        total = stats[:total_entries]
        return 0 if total.zero?

        score = 0

        # Frontmatter coverage (30 points)
        frontmatter_pct = (stats[:with_frontmatter].to_f / total * 100).round
        score += 30 if frontmatter_pct > 80
        score += 20 if frontmatter_pct > 50 && frontmatter_pct <= 80
        score += 10 if frontmatter_pct > 20 && frontmatter_pct <= 50

        # Tags coverage (20 points)
        tags_pct = (stats[:with_tags].to_f / total * 100).round
        score += 20 if tags_pct > 60
        score += 10 if tags_pct > 30 && tags_pct <= 60

        # Links coverage (20 points)
        links_pct = (stats[:with_links].to_f / total * 100).round
        score += 20 if links_pct > 40
        score += 10 if links_pct > 20 && links_pct <= 40

        # Embedding coverage (15 points)
        embedding_pct = (stats[:with_embeddings].to_f / total * 100).round
        score += 15 if embedding_pct > 80
        score += 8 if embedding_pct > 50 && embedding_pct <= 80

        # High confidence ratio (15 points)
        high_confidence = stats[:by_confidence]["high"] || 0
        high_confidence_pct = (high_confidence.to_f / total * 100).round
        score += 15 if high_confidence_pct > 50
        score += 8 if high_confidence_pct > 25 && high_confidence_pct <= 50

        score
      end

      def format_health_report(stats)
        report = []
        report << "# Memory Health Report"
        report << ""
        report << "## Overview"
        report << "- Total entries: #{stats[:total_entries]}"
        report << "- Total size: #{format_bytes(stats[:total_size])}"
        report << "- Entries with frontmatter: #{stats[:with_frontmatter]} (#{percentage(stats[:with_frontmatter], stats[:total_entries])}%)"
        report << "- Entries with embeddings: #{stats[:with_embeddings]} (#{percentage(stats[:with_embeddings], stats[:total_entries])}%)"
        report << "- Entries with tags: #{stats[:with_tags]} (#{percentage(stats[:with_tags], stats[:total_entries])}%)"
        report << "- Entries with related links: #{stats[:with_links]} (#{percentage(stats[:with_links], stats[:total_entries])}%)"
        report << "- Average quality score: #{stats[:average_quality]}/100"
        report << ""

        unless stats[:by_type].empty?
          report << "## By Type"
          stats[:by_type].sort_by { |_, count| -count }.each do |type, count|
            report << "- #{type}: #{count} (#{percentage(count, stats[:total_entries])}%)"
          end
          report << ""
        end

        unless stats[:by_confidence].empty?
          report << "## By Confidence"
          confidence_order = { "high" => 0, "medium" => 1, "low" => 2 }
          stats[:by_confidence].sort_by { |k, _| confidence_order[k] || 999 }.each do |conf, count|
            report << "- #{conf}: #{count} (#{percentage(count, stats[:total_entries])}%)"
          end
          report << ""
        end

        report << "## Health Score: #{stats[:health_score]}/100"
        report << health_score_interpretation(stats[:health_score])

        report.join("\n")
      end

      def percentage(part, total)
        return 0 if total.zero?

        ((part.to_f / total) * 100).round
      end

      def health_score_interpretation(score)
        case score
        when 80..100
          "Excellent - Memory is well-organized and high-quality"
        when 60..79
          "Good - Memory is decent but could use some improvements"
        when 40..59
          "Fair - Consider running defrag to improve organization"
        when 20..39
          "Poor - Memory needs significant cleanup and reorganization"
        else
          "Critical - Memory is poorly organized and needs immediate attention"
        end
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

      # Calculate quality score from metadata (not content parsing)
      #
      # @param metadata [Hash] Metadata hash from .yml file (string keys)
      # @return [Integer] Quality score 0-100
      def calculate_quality_from_metadata(metadata)
        return 0 if metadata.nil? || metadata.empty?

        score = 0

        # All keys are strings (no defensive || checks needed)
        score += 20 if metadata["type"]
        score += 20 if metadata["confidence"]
        score += 15 unless (metadata["tags"] || []).empty?
        score += 15 unless (metadata["related"] || []).empty?
        score += 10 if metadata["domain"]
        score += 10 if metadata["last_verified"]
        score += 10 if metadata["confidence"] == "high"

        score
      end
    end
  end
end
