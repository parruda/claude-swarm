# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

Minitest::TestTask.create(:test) do |t|
  t.test_globs = ["test/**/*_test.rb"]
  t.warning = false
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

RuboCop::RakeTask.new

task default: [:test, :rubocop]
