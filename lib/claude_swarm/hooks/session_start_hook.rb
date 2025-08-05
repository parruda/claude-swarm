#!/usr/bin/env ruby
# frozen_string_literal: true

# This hook is called when Claude Code starts a session
# It saves the transcript path for the main instance so the orchestrator can tail it

require "json"
require "fileutils"

# Read input from stdin
begin
  stdin_data = $stdin.read
  input = JSON.parse(stdin_data)
rescue => e
  # Return error response
  puts JSON.generate({
    "success" => false,
    "error" => "Failed to read/parse input: #{e.message}",
  })
  exit(1)
end

# Get session path from command-line argument or environment
session_path = ARGV[0] || ENV["CLAUDE_SWARM_SESSION_PATH"]

if session_path && input["transcript_path"]
  # Write the transcript path to a known location
  path_file = File.join(session_path, "main_instance_transcript.path")
  File.write(path_file, input["transcript_path"])

  # Return success
  puts JSON.generate({
    "success" => true,
  })
else
  # Return error if missing required data
  puts JSON.generate({
    "success" => false,
    "error" => "Missing session path or transcript path",
  })
  exit(1)
end
