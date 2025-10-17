#!/usr/bin/env ruby
# frozen_string_literal: true

# Example hook script: Validate Bash commands
#
# This demonstrates SwarmSDK hooks with JSON I/O and exit codes.
#
# Exit codes:
#   0 - Success (continue execution)
#   2 - Block execution with error feedback to LLM
#   Other - Non-blocking error (log warning, continue)
#
# Input (stdin): JSON with event details
# Output (stdout): JSON with success/error info

require "json"

# Read input from stdin
begin
  input_data = JSON.parse($stdin.read)
rescue JSON::ParserError => e
  $stderr.puts JSON.generate(success: false, error: "Invalid JSON input: #{e.message}")
  exit(1)
end

# Extract command from parameters
parameters = input_data["parameters"] || {}
command = parameters["command"] || ""

# Define dangerous patterns
dangerous_patterns = [
  [%r{rm\s+-rf\s+/}, "Recursive force removal from root"],
  [/dd\s+if=/, "dd command (can overwrite data)"],
  [/mkfs/, "Filesystem formatting"],
  [/:\(\)\{.*\|.*&\};:/, "Fork bomb pattern"],
  [%r{>\s*/dev/sd}, "Writing to disk devices"],
  [/chmod\s+777/, "Insecure permissions"],
]

# Check for dangerous patterns
dangerous_patterns.each do |pattern, description|
  next unless command.match?(pattern)

  # Exit 2 to block with error
  output = {
    success: false,
    error: "Dangerous command blocked: #{description}\nCommand: #{command}",
  }
  puts JSON.generate(output)
  exit 2 # Exit 2 = block execution
end

# Validation passed - allow execution
output = {
  success: true,
  message: "Bash command validation passed",
}
puts JSON.generate(output)
exit 0 # Exit 0 = continue
