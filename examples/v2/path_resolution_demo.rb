#!/usr/bin/env ruby
# frozen_string_literal: true

# Path Resolution Demo
#
# Demonstrates how SwarmSDK resolves file paths relative to agent directories.
# This is a CRITICAL feature introduced in v1.0 that ensures agents operate
# in their configured directory, not Dir.pwd.
#
# Key Concepts:
# 1. Each agent has a `directory` (singular) configuration
# 2. Relative paths in file tools are resolved against this directory
# 3. Absolute paths are used as-is
# 4. This is fiber-safe (no reliance on Dir.pwd)
#
# Run: bundle exec ruby -Ilib lib/swarm_sdk/examples/path_resolution_demo.rb

require "swarm_sdk"
require "fileutils"
require "tmpdir"

ENV["OPENAI_API_KEY"] = "test-key"

# Create a test directory structure for demonstration
demo_root = File.join(Dir.tmpdir, "swarm_path_demo_#{Process.pid}")
FileUtils.mkdir_p(demo_root)

# Create subdirectories
frontend_dir = File.join(demo_root, "frontend")
backend_dir = File.join(demo_root, "backend")
shared_dir = File.join(demo_root, "shared")

FileUtils.mkdir_p([frontend_dir, backend_dir, shared_dir])

# Create test files
File.write(File.join(frontend_dir, "index.html"), "<html><body>Frontend</body></html>")
File.write(File.join(backend_dir, "server.rb"), "puts 'Backend server'")
File.write(File.join(shared_dir, "config.yml"), "shared: true")
File.write(File.join(demo_root, "README.md"), "# Project Root")

puts "=" * 80
puts "PATH RESOLUTION DEMO"
puts "=" * 80
puts ""
puts "Test directory structure created at: #{demo_root}"
puts ""
puts "Directory structure:"
puts "  #{demo_root}/"
puts "    ├── README.md"
puts "    ├── frontend/"
puts "    │   └── index.html"
puts "    ├── backend/"
puts "    │   └── server.rb"
puts "    └── shared/"
puts "        └── config.yml"
puts ""
puts "=" * 80
puts ""

# Build a swarm with agents in different directories
swarm = SwarmSDK.build do
  name("Path Resolution Demo Swarm")
  lead(:coordinator)

  # Coordinator works in project root
  agent(:coordinator) do
    description("Coordinator working in project root")
    model("gpt-5-nano")
    provider("openai")

    # This agent's directory is the project root
    directory(demo_root)

    tools(:Read, :Write, :Glob)
    delegates_to(:frontend_agent, :backend_agent)

    system_prompt(<<~PROMPT)
      You demonstrate path resolution behavior in SwarmSDK.

      Your working directory is: #{demo_root}

      When you use file tools:
      - Relative paths like "README.md" resolve to #{File.join(demo_root, "README.md")}
      - Relative paths like "frontend/index.html" resolve to #{File.join(demo_root, "frontend/index.html")}
      - Absolute paths like "/tmp/test.txt" are used as-is

      Demonstrate this by:
      1. Reading "README.md" (relative path)
      2. Listing files with Glob("*") (relative pattern)
      3. Trying to access files in subdirectories
    PROMPT
  end

  # Frontend agent works in frontend/ directory
  agent(:frontend_agent) do
    description("Frontend agent working in frontend/ directory")
    model("gpt-5-nano")
    provider("openai")

    # This agent's directory is frontend/
    directory(frontend_dir)

    tools(:Read, :Write, :Glob)

    system_prompt(<<~PROMPT)
      You are a frontend agent working in: #{frontend_dir}

      Path resolution for your tools:
      - Relative path "index.html" → #{File.join(frontend_dir, "index.html")}
      - Relative path "../shared/config.yml" → #{File.join(demo_root, "shared/config.yml")}
      - Absolute paths are used as-is

      When asked to demonstrate:
      1. Read "index.html" (relative path in your directory)
      2. Try to read "../shared/config.yml" (relative path to parent)
      3. List files with Glob("*.html") (relative pattern)
    PROMPT
  end

  # Backend agent works in backend/ directory
  agent(:backend_agent) do
    description("Backend agent working in backend/ directory")
    model("gpt-5-nano")
    provider("openai")

    # This agent's directory is backend/
    directory(backend_dir)

    tools(:Read, :Write, :Glob)

    system_prompt(<<~PROMPT)
      You are a backend agent working in: #{backend_dir}

      Path resolution for your tools:
      - Relative path "server.rb" → #{File.join(backend_dir, "server.rb")}
      - Relative path "../README.md" → #{File.join(demo_root, "README.md")}
      - Absolute paths are used as-is

      When asked to demonstrate:
      1. Read "server.rb" (relative path in your directory)
      2. Try to read "../README.md" (relative path to parent)
      3. List files with Glob("*.rb") (relative pattern)
    PROMPT
  end
end

puts "✅ Swarm created with 3 agents in different directories"
puts ""
puts "Agent Directories:"
puts "  coordinator    → #{demo_root}"
puts "  frontend_agent → #{frontend_dir}"
puts "  backend_agent  → #{backend_dir}"
puts ""
puts "=" * 80
puts ""

# Verify agent configurations
puts "AGENT CONFIGURATIONS:"
puts "-" * 80
swarm.agent_names.each do |agent_name|
  agent_def = swarm.agent_definition(agent_name)
  puts "#{agent_name}:"
  puts "  directory: #{agent_def.directory}"
  puts "  tools: #{agent_def.tools.map { |t| t[:name] }.join(", ")}"
  puts ""
end

puts "PATH RESOLUTION EXAMPLES:"
puts "-" * 80
puts ""
puts "Coordinator (directory: #{demo_root}):"
puts "  'README.md' → #{File.join(demo_root, "README.md")}"
puts "  'frontend/index.html' → #{File.join(demo_root, "frontend/index.html")}"
puts ""
puts "Frontend Agent (directory: #{frontend_dir}):"
puts "  'index.html' → #{File.join(frontend_dir, "index.html")}"
puts "  '../shared/config.yml' → #{File.join(demo_root, "shared/config.yml")}"
puts "  '../README.md' → #{File.join(demo_root, "README.md")}"
puts ""
puts "Backend Agent (directory: #{backend_dir}):"
puts "  'server.rb' → #{File.join(backend_dir, "server.rb")}"
puts "  '../shared/config.yml' → #{File.join(demo_root, "shared/config.yml")}"
puts "  '../README.md' → #{File.join(demo_root, "README.md")}"
puts ""

# Uncomment below to test with actual LLM calls (requires API key and time)
# puts "LIVE TESTS (uncomment to run):"
# puts "-" * 80
# result = swarm.execute("Read the file 'README.md' and tell me what it contains.")
# puts "Result: #{result.content}"
# puts ""

puts "=" * 80
puts "KEY TAKEAWAYS"
puts "=" * 80
puts ""
puts "1. Each agent has ONE directory (singular, not plural)"
puts "2. Relative paths are resolved against the agent's directory"
puts "3. Absolute paths are used as-is"
puts "4. Agents can access parent/sibling dirs via '../' relative paths"
puts "5. This is fiber-safe and doesn't rely on Dir.pwd"
puts ""
puts "MIGRATION NOTE:"
puts "  OLD (v0.x): directories: ['.', 'lib/', 'test/']  # Multiple dirs"
puts "  NEW (v1.0): directory: 'lib/'                    # Single dir"
puts ""
puts "For multi-directory access, use permissions:"
puts "  directory: 'lib/'"
puts "  permissions:"
puts "    Read:"
puts "      allowed_paths: ['../test/**']"
puts ""

# Cleanup
FileUtils.rm_rf(demo_root)
puts "✅ Demo complete! Test directory cleaned up."
