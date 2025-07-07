# frozen_string_literal: true

require "claude_swarm"

Gem::Specification.new do |spec|
  spec.name = "claude-swarm"
  spec.version = ClaudeSwarm::VERSION
  spec.authors = ["Paulo Arruda"]
  spec.email = ["parrudaj@gmail.com"]

  spec.summary = "Alias gem for claude_swarm - Orchestrate multiple Claude Code instances"
  spec.description = <<~DESC
    This is an alias gem for claude_swarm. Install this if you prefer the hyphenated name.

    Claude Swarm enables you to run multiple Claude Code instances that communicate with each other
    via MCP (Model Context Protocol). Create AI development teams where each instance has specialized
    roles, tools, and directory contexts.
  DESC
  spec.homepage = "https://github.com/parruda/claude-swarm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/parruda/claude-swarm"
  spec.metadata["changelog_uri"] = "https://github.com/parruda/claude-swarm/blob/main/CHANGELOG.md"

  spec.files = ["lib/claude-swarm.rb", "claude-swarm.gemspec", "README.md"]
  spec.require_paths = ["lib"]

  # This gem simply depends on the main claude_swarm gem
  spec.add_dependency("claude_swarm")
end
