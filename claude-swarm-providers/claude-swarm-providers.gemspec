# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "claude-swarm-providers"
  spec.version = "0.1.0"
  spec.authors = ["Claude Swarm Team"]
  spec.email = ["support@example.com"]

  spec.summary = "Multi-provider support for Claude Swarm"
  spec.description = "Adds support for OpenAI, Google Gemini, Cohere, and other LLM providers to Claude Swarm via the ruby_llm gem"
  spec.homepage = "https://github.com/parruda/claude-swarm"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/parruda/claude-swarm"
  spec.metadata["changelog_uri"] = "https://github.com/parruda/claude-swarm/blob/main/CHANGELOG.md"

  # This gem has no actual code - it just installs dependencies
  spec.files = ["lib/claude_swarm_providers.rb"]

  # Add runtime dependencies
  spec.add_dependency "claude-swarm", "~> 0.1"
  spec.add_dependency "ruby_llm", "~> 0.1"
  spec.add_dependency "ruby_llm-mcp", "~> 0.1"
end
