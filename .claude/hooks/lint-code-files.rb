#!/usr/bin/env ruby
# frozen_string_literal: true

require "English"
require "json"

begin
  # Read JSON input from stdin
  input = JSON.parse($stdin.read)

  # Extract the file path from the tool input
  file_path = input.dig("tool_input", "file_path") || ""

  # Determine which linters to run based on file extension
  # Exclude .md.erb files (markdown templates) from RuboCop
  run_rubocop = file_path.end_with?(".rb", ".jbuilder", ".html.erb") ||
    (file_path.end_with?(".erb") && !file_path.end_with?(".md.erb"))
  run_erblint = file_path.end_with?(".erb", ".html.erb")

  if !run_rubocop && !run_erblint
    exit(0)
  end

  # Change to project directory
  project_dir = ENV["CLAUDE_PROJECT_DIR"]
  unless project_dir
    puts "⚠️  CLAUDE_PROJECT_DIR not set - cannot run linters"
    exit(0)
  end

  Dir.chdir(project_dir) do
    errors = []

    # Run RuboCop if applicable
    if run_rubocop
      %x(bundle exec rubocop -A #{file_path} 2>&1)
      exit_code = $CHILD_STATUS.exitstatus

      if exit_code != 0
        result = %x(bundle exec rubocop -A #{file_path} 2>&1) # Run again so we only get the issues.
        puts "⚠️  RuboCop found issues:"
        puts result
        errors << "RuboCop found issues that need manual fixing:\n#{result}"
      end
    end

    # Report any errors
    if errors.any?
      puts "Please review the remaining issues above and fix them."

      # Exit with code 2 to make stderr visible to Claude
      $stderr.puts errors.join("\n\n")
      exit(2)
    end
  end
rescue JSON::ParserError => e
  $stderr.puts "Error parsing JSON: #{e.message}"
  exit(1)
rescue StandardError => e
  $stderr.puts "Error: #{e.message}"
  exit(1)
end

# Success case - exit with 0 to show stdout in transcript mode
exit(0)
