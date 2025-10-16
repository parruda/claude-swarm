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
    t.test_globs = ["test/**/*_test.rb"]
    t.test_globs -= ["test/swarm_sdk/**/*_test.rb"]
    t.warning = false
  end

  RuboCop::RakeTask.new(:rubocop) do |t|
    t.patterns = ["lib/claude_swarm.rb", "lib/claude_swarm/**/*.rb", "test/**/*_test.rb"]
    t.patterns -= ["test/swarm_sdk/**/*.rb"]
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

RuboCop::RakeTask.new

task default: [:test, :rubocop]
