# frozen_string_literal: true

require_relative "lib/claude_swarm_multi_model/version"

Gem::Specification.new do |spec|
  spec.name = "claude-swarm-multi-model"
  spec.version = ClaudeSwarmMultiModel::VERSION
  spec.authors = ["Claude Swarm Contributors"]
  spec.email = ["support@claude-swarm.dev"]

  spec.summary = "Multi-model support extension for Claude Swarm"
  spec.description = "Enables orchestration of AI agents across different model providers (OpenAI, Google, Anthropic, Cohere) in Claude Swarm"
  spec.homepage = "https://github.com/parruda/claude-swarm-multi-model"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|github))})
    end
  end
  spec.bindir = "exe"
  spec.executables = %w[claude-swarm-multi-model claude-swarm-llm-mcp]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "claude-swarm", "~> 0.1"
  spec.add_dependency "fast-mcp-annotations", "~> 0.3"
  spec.add_dependency "ruby_llm", "~> 0.1"
  spec.add_dependency "thor", "~> 1.3"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-minitest", "~> 0.20.1"
  spec.add_development_dependency "rubocop-rake", "~> 0.6.0"
end
