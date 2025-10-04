# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class AgentDefinitionTest < Minitest::Test
    def test_initialization_with_required_fields
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "You are a test agent",
          directories: ["."],
        },
      )

      assert_equal(:test_agent, agent_def.name)
      assert_equal("Test agent", agent_def.description)
      assert_equal("You are a test agent", agent_def.system_prompt)
      assert_equal([File.expand_path(".")], agent_def.directories)
    end

    def test_initialization_with_defaults
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "Test prompt",
          directories: ["."],
        },
      )

      assert_equal("gpt-5", agent_def.model)
      assert_equal("openai", agent_def.provider)
      assert_empty(agent_def.tools)
      assert_empty(agent_def.delegates_to)
      assert_empty(agent_def.mcp_servers)
    end

    def test_initialization_with_all_fields
      agent_def = AgentDefinition.new(
        :full_agent,
        {
          description: "Full agent",
          model: "claude-sonnet-4",
          system_prompt: "You are full",
          provider: "anthropic",
          base_url: "https://api.anthropic.com",
          parameters: {
            temperature: 0.7,
            max_tokens: 4000,
            reasoning_effort: "high",
          },
          directories: [".", "./lib"],
          tools: [:Read, :Edit, :Bash],
          delegates_to: [:backend, :frontend],
          mcp_servers: [{ type: :stdio, command: "test" }],
        },
      )

      assert_equal("claude-sonnet-4", agent_def.model)
      assert_equal("anthropic", agent_def.provider)
      assert_in_delta(0.7, agent_def.parameters[:temperature])
      assert_equal(4000, agent_def.parameters[:max_tokens])
      assert_equal("https://api.anthropic.com", agent_def.base_url)
      assert_equal("high", agent_def.parameters[:reasoning_effort])
      assert_equal(2, agent_def.directories.length)
      assert_equal([:Read, :Edit, :Bash], agent_def.tools)
      assert_equal([:backend, :frontend], agent_def.delegates_to)
      assert_equal(1, agent_def.mcp_servers.length)
    end

    def test_missing_description_raises_error
      error = assert_raises(ConfigurationError) do
        AgentDefinition.new(
          :test_agent,
          {
            system_prompt: "Test prompt",
            directories: ["."],
          },
        )
      end

      assert_match(/missing required 'description' field/i, error.message)
    end

    def test_missing_system_prompt_raises_error
      error = assert_raises(ConfigurationError) do
        AgentDefinition.new(
          :test_agent,
          {
            description: "Test agent",
            directories: ["."],
          },
        )
      end

      assert_match(/missing required 'system_prompt' field/i, error.message)
    end

    def test_nonexistent_directory_raises_error
      error = assert_raises(ConfigurationError) do
        AgentDefinition.new(
          :test_agent,
          {
            description: "Test agent",
            system_prompt: "Test prompt",
            directories: ["/nonexistent/path"],
          },
        )
      end

      assert_match(/directory.*does not exist/i, error.message)
    end

    def test_parse_directories_with_nil
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "Test prompt",
        },
      )

      assert_equal([File.expand_path(".")], agent_def.directories)
    end

    def test_parse_directories_with_single_string
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "Test prompt",
          directories: ".",
        },
      )

      assert_equal([File.expand_path(".")], agent_def.directories)
    end

    def test_parse_directories_with_array
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "Test prompt",
          directories: [".", "./lib"],
        },
      )

      assert_equal(2, agent_def.directories.length)
      assert_includes(agent_def.directories, File.expand_path("."))
      assert_includes(agent_def.directories, File.expand_path("./lib"))
    end

    def test_directories_are_expanded
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "Test prompt",
          directories: ["./lib"],
        },
      )

      refute_includes(agent_def.directories, "./lib")
      assert_includes(agent_def.directories, File.expand_path("./lib"))
    end

    def test_to_h_returns_complete_hash
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          model: "gpt-5",
          system_prompt: "Test prompt",
          provider: "openai",
          base_url: "https://api.openai.com",
          parameters: {
            temperature: 0.8,
            max_tokens: 2000,
            reasoning_effort: "medium",
          },
          directories: ["."],
          tools: [:Read],
          delegates_to: [:backend],
          mcp_servers: [{ type: :stdio }],
        },
      )

      hash = agent_def.to_h

      assert_equal(:test_agent, hash[:name])
      assert_equal("Test agent", hash[:description])
      assert_equal("gpt-5", hash[:model])
      assert_equal("Test prompt", hash[:system_prompt])
      assert_equal("openai", hash[:provider])
      assert_in_delta(0.8, hash[:parameters][:temperature])
      assert_equal(2000, hash[:parameters][:max_tokens])
      assert_equal("https://api.openai.com", hash[:base_url])
      assert_equal("medium", hash[:parameters][:reasoning_effort])
      assert_equal(agent_def.directories, hash[:directories])
      assert_equal([:Read], hash[:tools])
      assert_equal([:backend], hash[:delegates_to])
      assert_equal([{ type: :stdio }], hash[:mcp_servers])
    end

    def test_to_h_omits_nil_values
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "Test prompt",
          directories: ["."],
        },
      )

      hash = agent_def.to_h

      # Has non-nil values
      assert(hash.key?(:name))
      assert(hash.key?(:description))
      assert(hash.key?(:system_prompt))

      # Omits nil values (compact removes them)
      refute(hash.key?(:temperature))
      refute(hash.key?(:max_tokens))
      refute(hash.key?(:base_url))
      refute(hash.key?(:reasoning_effort))
    end

    def test_attr_readers
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "Test prompt",
          directories: ["."],
        },
      )

      assert_respond_to(agent_def, :name)
      assert_respond_to(agent_def, :description)
      assert_respond_to(agent_def, :model)
      assert_respond_to(agent_def, :directories)
      assert_respond_to(agent_def, :tools)
      assert_respond_to(agent_def, :delegates_to)
      assert_respond_to(agent_def, :system_prompt)
      assert_respond_to(agent_def, :provider)
      assert_respond_to(agent_def, :base_url)
      assert_respond_to(agent_def, :mcp_servers)
      assert_respond_to(agent_def, :parameters)
      assert_respond_to(agent_def, :timeout)
    end

    def test_default_timeout_constant
      assert_equal(300, AgentDefinition::DEFAULT_TIMEOUT)
    end

    def test_timeout_defaults_to_300_seconds
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "Test prompt",
          directories: ["."],
        },
      )

      assert_equal(300, agent_def.timeout)
    end

    def test_timeout_can_be_customized
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "Test prompt",
          directories: ["."],
          timeout: 600,
        },
      )

      assert_equal(600, agent_def.timeout)
    end

    def test_to_h_includes_timeout
      agent_def = AgentDefinition.new(
        :test_agent,
        {
          description: "Test agent",
          system_prompt: "Test prompt",
          directories: ["."],
          timeout: 450,
        },
      )

      hash = agent_def.to_h

      assert_equal(450, hash[:timeout])
    end
  end
end
