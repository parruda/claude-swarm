# frozen_string_literal: true

require_relative "lib/swarm_cli/version"

Gem::Specification.new do |spec|
  spec.name = "swarm_cli"
  spec.version = SwarmCLI::VERSION
  spec.authors = ["Paulo Arruda"]
  spec.email = ["parrudaj@gmail.com"]

  spec.summary = "Command-line interface for SwarmSDK"
  spec.description = <<~DESC
    SwarmCLI provides a beautiful command-line interface for SwarmSDK, the lightweight multi-agent
    AI orchestration framework. Built with the TTY toolkit, it offers an intuitive and interactive
    way to define, manage, and execute AI agent swarms with progress indicators, formatted output,
    and comprehensive help documentation.
  DESC
  spec.homepage = "https://github.com/parruda/claude-swarm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["source_code_uri"] = "https://github.com/parruda/claude-swarm"
  spec.metadata["changelog_uri"] = "https://github.com/parruda/claude-swarm/blob/main/docs/v2/CHANGELOG.swarm_cli.md"

  File.basename(__FILE__)
  spec.files = IO.popen(["git", "ls-files", "-z"], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |f|
      (f == "lib/swarm_cli.rb") ||
        f.match?(%r{\Alib/swarm_cli/}) ||
        (f == "exe/swarm")
    end
  end
  spec.bindir = "exe"
  spec.executables = ["swarm"]
  spec.require_paths = ["lib"]

  spec.add_dependency("fast-mcp", "~> 1.6")
  spec.add_dependency("pastel")
  spec.add_dependency("swarm_sdk", "~> 2.1")
  spec.add_dependency("tty-box")
  spec.add_dependency("tty-cursor")
  spec.add_dependency("tty-link")
  spec.add_dependency("tty-markdown")
  spec.add_dependency("tty-option")
  spec.add_dependency("tty-spinner")
  spec.add_dependency("tty-tree")
  spec.add_dependency("zeitwerk")

  # NOTE: Reline is part of Ruby stdlib (since 2.7), no gem dependency needed

  # Document parsing for Read tool
  spec.add_dependency("csv")
  spec.add_dependency("docx", "~> 0.10")
  spec.add_dependency("pdf-reader", "~> 2.15")
  spec.add_dependency("reverse_markdown", "~> 3.0.0")
  spec.add_dependency("roo", "~> 3.0.0")
end
