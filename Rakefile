# frozen_string_literal: true

require "minitest/test_task"
require "rubocop/rake_task"

# Run all tests (both claude_swarm and swarm_sdk)
Minitest::TestTask.create(:test) do |t|
  t.test_globs = ["test/**/*_test.rb"]
  t.warning = false
end

namespace :claude_swarm do
  Minitest::TestTask.create(:test) do |t|
    # Expand globs and subtract to get only claude_swarm tests
    all_tests = Dir.glob("test/**/*_test.rb")
    exclude_tests = Dir.glob("test/swarm_sdk/**/*_test.rb") +
      Dir.glob("test/swarm_memory/**/*_test.rb") +
      Dir.glob("test/swarm_cli/**/*_test.rb")
    t.test_globs = all_tests - exclude_tests
    t.warning = false
  end

  RuboCop::RakeTask.new(:rubocop) do |t|
    # Expand patterns and subtract
    all_patterns = Dir.glob("lib/claude_swarm.rb") + Dir.glob("lib/claude_swarm/**/*.rb") + Dir.glob("test/**/*_test.rb")
    exclude_patterns = Dir.glob("test/swarm_sdk/**/*.rb") +
      Dir.glob("test/swarm_memory/**/*.rb") +
      Dir.glob("test/swarm_cli/**/*.rb")
    t.patterns = all_patterns - exclude_patterns
  end

  desc "Run ClaudeSwarm tests and linting"
  task all: [:test, :rubocop]
end

namespace :swarm_sdk do
  Minitest::TestTask.create(:test) do |t|
    t.test_globs = ["test/swarm_sdk/**/*_test.rb"]
    t.warning = false
  end

  RuboCop::RakeTask.new(:rubocop) do |t|
    t.patterns = ["lib/swarm_sdk.rb", "lib/swarm_sdk/**/*.rb", "test/swarm_sdk/**/*.rb"]
  end

  desc "Run SwarmSDK tests and linting"
  task all: [:test, :rubocop]
end

namespace :swarm_cli do
  Minitest::TestTask.create(:test) do |t|
    t.test_globs = ["test/swarm_cli/**/*_test.rb"]
    t.warning = false
  end

  RuboCop::RakeTask.new(:rubocop) do |t|
    t.patterns = ["lib/swarm_cli.rb", "lib/swarm_cli/**/*.rb", "test/swarm_cli/**/*.rb"]
  end

  desc "Run SwarmCLI tests and linting"
  task all: [:test, :rubocop]
end

namespace :swarm_memory do
  Minitest::TestTask.create(:test) do |t|
    t.test_globs = ["test/swarm_memory/**/*_test.rb"]
    t.warning = false
  end

  RuboCop::RakeTask.new(:rubocop) do |t|
    t.patterns = ["lib/swarm_memory.rb", "lib/swarm_memory/**/*.rb", "test/swarm_memory/**/*.rb"]
  end

  desc "Run SwarmMemory tests and linting"
  task all: [:test, :rubocop]
end

RuboCop::RakeTask.new

task default: [:test, :rubocop]
