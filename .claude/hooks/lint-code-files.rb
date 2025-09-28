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
  run_rubocop = file_path.end_with?(".rb", ".jbuilder", ".erb")
  run_erblint = file_path.end_with?(".erb", ".html.erb")

  if !run_rubocop && !run_erblint
    puts "ℹ️  Skipping linting - #{file_path} is not a Ruby, JBuilder, or ERB file"
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
      puts "🔍 Running RuboCop with auto-correct on #{file_path}..."
      result = %x(bundle exec rubocop -A #{file_path} 2>&1)
      exit_code = $CHILD_STATUS.exitstatus

      if exit_code == 0
        puts "✅ RuboCop passed - no issues found"
      else
        puts "⚠️  RuboCop found issues:"
        puts result
        errors << "RuboCop found issues that need manual fixing:\n#{result}"
      end
    end

    # Run erb_lint if applicable
    if run_erblint
      puts "🔍 Running ERB Lint with auto-correct on #{file_path}..."
      result = %x(bundle exec erb_lint --autocorrect #{file_path} 2>&1)
      exit_code = $CHILD_STATUS.exitstatus

      if exit_code == 0
        puts "✅ ERB Lint passed - no issues found"
      else
        puts "⚠️  ERB Lint found issues:"
        puts result
        errors << "ERB Lint found issues that need manual fixing:\n#{result}"
      end
    end

    # Report any errors
    if errors.any?
      puts "\n📝 Some issues may have been auto-corrected."
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
