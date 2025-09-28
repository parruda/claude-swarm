# frozen_string_literal: true

require_relative "lib/swarm_core/version"

Gem::Specification.new do |spec|
  spec.name = "swarm_core"
  spec.version = SwarmCore::VERSION
  spec.authors = ["Paulo Arruda"]
  spec.email = ["parrudaj@gmail.com"]

  spec.summary = "Lightweight multi-agent AI orchestration using RubyLLM"
  spec.description = <<~DESC
    SwarmCore is a complete reimagining of Claude Swarm that runs all AI agents in a single process
    using RubyLLM for LLM interactions. Define collaborative AI agents in simple Markdown files with
    YAML frontmatter, and orchestrate them without the overhead of multiple processes or MCP
    inter-process communication. Perfect for building lightweight, efficient AI agent teams with
    specialized roles and capabilities.
  DESC
  spec.homepage = "https://github.com/parruda/claude-swarm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/parruda/claude-swarm"
  spec.metadata["changelog_uri"] = "https://github.com/parruda/claude-swarm/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(["git", "ls-files", "-z"], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |f|
      f.start_with?("lib/swarm_core/") || f == "lib/swarm_core.rb" || f.start_with?("exe/swarm")
    end
  end
  spec.bindir = "exe"
  spec.executables = ["swarm"]
  spec.require_paths = ["lib"]

  spec.add_dependency("ruby_llm")
  spec.add_dependency("thor", "~> 1.3")
  spec.add_dependency("zeitwerk", "~> 2.6")
end
