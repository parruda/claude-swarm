#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "swarm_sdk"

# Example: Learning Assistant with Persistent Memory
#
# This demonstrates a continuously learning agent that:
# - Starts with zero knowledge
# - Learns through tools and user interaction
# - Stores knowledge in organized memory
# - Recalls from memory in future sessions
# - Evolves and improves over time

SwarmSDK.build do
  name("Learning Assistant")
  lead(:assistant)
  use_scratchpad(true) # default

  # Load agent from markdown file (includes system prompt with memory schema)
  agent(:assistant, File.read("examples/learning-assistant/assistant.md")) do
    # Configure persistent memory for learning

    memory do
      adapter :filesystem # default, can omit
      directory ".swarm/learning-assistant"
    end

    # Memory tools will be automatically added because memory is configured
    # Default tools are still available: Read, Grep, Glob, WebFetch, Think, TodoWrite
    # Scratchpad tools are available: ScratchpadWrite, ScratchpadRead, ScratchpadList
  end
end
