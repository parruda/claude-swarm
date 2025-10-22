# frozen_string_literal: true

# Load dependencies first (before Zeitwerk)
require "json"
require "yaml"
require "fileutils"
require "time"
require "date"
require "set"

require "async"
require "async/semaphore"
require "swarm_sdk"
require "ruby_llm"

# Try to load informers (optional, for embeddings)
begin
  require "informers"
rescue LoadError
  # Informers not available - embeddings will be disabled
  warn("Warning: informers gem not found. Semantic search will be unavailable. Run: gem install informers")
end

# Load errors and version first
require_relative "swarm_memory/errors"
require_relative "swarm_memory/version"

# Setup Zeitwerk loader
require "zeitwerk"
loader = Zeitwerk::Loader.new
loader.push_dir("#{__dir__}/swarm_memory", namespace: SwarmMemory)
loader.setup

module SwarmMemory
  class << self
    # Create individual tool instance
    # Called by SwarmSDK's ToolConfigurator
    #
    # @param tool_name [Symbol] Tool name
    # @param storage [SwarmMemory::Core::Storage] Storage instance
    # @param agent_name [String, Symbol] Agent identifier
    # @return [RubyLLM::Tool] Configured tool instance
    def create_tool(tool_name, storage:, agent_name:)
      # Validate storage is present
      if storage.nil?
        raise ConfigurationError,
          "Cannot create #{tool_name} tool: memory storage is nil. " \
            "Did you configure memory for this agent? " \
            "Add: memory { directory '.swarm/agent-memory' }"
      end

      case tool_name.to_sym
      when :MemoryWrite
        Tools::MemoryWrite.new(storage: storage, agent_name: agent_name)
      when :MemoryRead
        Tools::MemoryRead.new(storage: storage, agent_name: agent_name)
      when :MemoryEdit
        Tools::MemoryEdit.new(storage: storage, agent_name: agent_name)
      when :MemoryMultiEdit
        Tools::MemoryMultiEdit.new(storage: storage, agent_name: agent_name)
      when :MemoryDelete
        Tools::MemoryDelete.new(storage: storage)
      when :MemoryGlob
        Tools::MemoryGlob.new(storage: storage)
      when :MemoryGrep
        Tools::MemoryGrep.new(storage: storage)
      when :MemoryDefrag
        Tools::MemoryDefrag.new(storage: storage)
      else
        raise ConfigurationError, "Unknown memory tool: #{tool_name}"
      end
    end

    # Convenience method for creating all memory tools at once
    # Useful for direct RubyLLM usage (not via SwarmSDK)
    #
    # @param storage [SwarmMemory::Core::Storage] Storage instance
    # @param agent_name [String, Symbol] Agent identifier
    # @return [Array<RubyLLM::Tool>] All configured memory tools
    def tools_for(storage:, agent_name:)
      [
        Tools::MemoryWrite.new(storage: storage, agent_name: agent_name),
        Tools::MemoryRead.new(storage: storage, agent_name: agent_name),
        Tools::MemoryEdit.new(storage: storage, agent_name: agent_name),
        Tools::MemoryMultiEdit.new(storage: storage, agent_name: agent_name),
        Tools::MemoryDelete.new(storage: storage),
        Tools::MemoryGlob.new(storage: storage),
        Tools::MemoryGrep.new(storage: storage),
        Tools::MemoryDefrag.new(storage: storage),
      ]
    end
  end
end

# Auto-register with SwarmSDK when loaded
require_relative "swarm_memory/integration/registration"
SwarmMemory::Integration::Registration.register!

# Auto-register CLI commands with SwarmCLI when loaded
require_relative "swarm_memory/integration/cli_registration"
SwarmMemory::Integration::CliRegistration.register!
