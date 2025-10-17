# frozen_string_literal: true

require_relative "lib/claude_swarm/version"

Gem::Specification.new do |spec|
  spec.name = "claude_swarm"
  spec.version = ClaudeSwarm::VERSION
  spec.authors = ["Paulo Arruda"]
  spec.email = ["parrudaj@gmail.com"]

  spec.summary = "Orchestrate multiple Claude Code instances as a collaborative AI development team"
  spec.description = <<~DESC
    Claude Swarm enables you to run multiple Claude Code instances that communicate with each other
    via MCP (Model Context Protocol). Create AI development teams where each instance has specialized
    roles, tools, and directory contexts. Define your swarm topology in simple YAML and let Claude
    instances collaborate across codebases. Perfect for complex projects requiring specialized AI
    agents for frontend, backend, testing, DevOps, or research tasks.
  DESC
  spec.homepage = "https://github.com/parruda/claude-swarm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["source_code_uri"] = "https://github.com/parruda/claude-swarm"
  spec.metadata["changelog_uri"] = "https://github.com/parruda/claude-swarm/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(["git", "ls-files", "-z"], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?("bin/", "test/", "spec/", "features/", ".git", "appveyor", "Gemfile") ||
        (f == "exe/claude-swarm")
    end
  end
  spec.bindir = "exe"
  spec.executables = ["claude-swarm"]
  spec.require_paths = ["lib"]

  spec.add_dependency("thor", "~> 1.3")
  spec.add_dependency("zeitwerk", "~> 2.6")

  spec.add_dependency("claude-code-sdk-ruby", "~> 0.1.6")
  spec.add_dependency("faraday-net_http_persistent", "~> 2.0")
  spec.add_dependency("faraday-retry", "~> 2.0")
  spec.add_dependency("fast-mcp", "~> 1.6")
  spec.add_dependency("ruby-mcp-client", "~> 0.7")
  spec.add_dependency("ruby-openai", ">= 7.0", "< 9.0")

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
