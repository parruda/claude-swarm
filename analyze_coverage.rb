#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

data = JSON.parse(File.read("coverage/.resultset.json"))
coverage = data["Minitest"]["coverage"]

# Find SwarmSDK files with branches
swarm_files_with_branches = coverage.select do |file, data|
  file.include?("/lib/swarm_sdk/") && data["branches"] && !data["branches"].empty?
end

puts "SwarmSDK Files with Branch Coverage Data:"
puts "=" * 80

results = []

swarm_files_with_branches.each do |file, data|
  branches = data["branches"]

  # Count total branch points
  # Each element in branches array is [branch_id, {path1 => count1, path2 => count2, ...}]
  total_branch_points = 0
  covered_branch_points = 0

  branches.each do |branch_info|
    next unless branch_info.is_a?(Array) && branch_info.size == 2

    branch_paths = branch_info[1]
    next unless branch_paths.is_a?(Hash)

    branch_paths.each do |_path, count|
      total_branch_points += 1
      covered_branch_points += 1 if count && count > 0
    end
  end

  coverage_pct = total_branch_points > 0 ? (covered_branch_points.to_f / total_branch_points * 100).round(2) : 0

  # Extract just the filename
  filename = file.split("/").last(3).join("/")

  results << {
    file: filename,
    full_path: file,
    covered: covered_branch_points,
    total: total_branch_points,
    pct: coverage_pct,
    uncovered_branches: branches.select do |branch_info|
      next false unless branch_info.is_a?(Array) && branch_info.size == 2

      branch_paths = branch_info[1]
      next false unless branch_paths.is_a?(Hash)

      # Check if ANY path is uncovered
      branch_paths.any? { |_path, count| count.nil? || count == 0 }
    end,
  }
end

# Sort by coverage percentage (ascending - worst first)
results.sort_by { |r| r[:pct] }.each do |r|
  puts format("%-50s %3d/%3d (%5.1f%%)", r[:file], r[:covered], r[:total], r[:pct])
end

puts "=" * 80
total_branches = results.sum { |r| r[:total] }
total_covered = results.sum { |r| r[:covered] }
overall_pct = total_branches > 0 ? (total_covered.to_f / total_branches * 100).round(2) : 0
puts format("Overall: %d/%d (%.2f%%)", total_covered, total_branches, overall_pct)
puts ""

# Show files with worst coverage (< 80%)
puts "\nFiles with < 80% branch coverage:"
puts "=" * 80
results.select { |r| r[:pct] < 80 }.sort_by { |r| r[:pct] }.each do |r|
  puts format("%-50s %3d/%3d (%5.1f%%)", r[:file], r[:covered], r[:total], r[:pct])

  # Show first few uncovered branches
  if r[:uncovered_branches].any?
    puts "  Uncovered branches:"
    r[:uncovered_branches].first(3).each do |branch_info|
      branch_id = branch_info[0]
      # Parse branch location from the string
      next unless branch_id =~ /\[:(if|unless|case|when), \d+, (\d+), (\d+)/

      branch_type = Regexp.last_match(1)
      line_num = Regexp.last_match(2)
      puts "    Line #{line_num}: #{branch_type} statement"
    end
  end
  puts ""
end
