# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

Minitest::TestTask.create(:test) do |t|
  t.test_globs = ["test/**/*_test.rb"]
  t.warning = false
end

namespace :swarm_core do
  Minitest::TestTask.create(:test) do |t|
    t.test_globs = ["test/swarm_core/**/*_test.rb"]
    t.warning = false
  end

  RuboCop::RakeTask.new(:rubocop) do |t|
    t.patterns = ["lib/swarm_core.rb", "lib/swarm_core/**/*.rb", "test/swarm_core/**/*.rb"]
  end

  desc "Run SwarmCore tests and linting"
  task all: [:test, :rubocop]
end

RuboCop::RakeTask.new

task default: [:test, :rubocop]
