# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ValidationAPITest < Minitest::Test
    def test_validate_returns_empty_array_for_valid_config
      yaml = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: backend
          agents:
            backend:
              description: "Backend developer"
              model: gpt-5
              directory: .
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_empty(errors, "Expected no validation errors for valid config")
    end

    def test_validate_missing_version
      yaml = <<~YAML
        swarm:
          name: "Test Swarm"
          lead: backend
          agents:
            backend:
              description: "Backend developer"
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:missing_field, error[:type])
      assert_equal("version", error[:field])
      assert_match(/Missing 'version' field/, error[:message])
    end

    def test_validate_invalid_version
      yaml = <<~YAML
        version: 1
        swarm:
          name: "Test Swarm"
          lead: backend
          agents:
            backend:
              description: "Backend developer"
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:invalid_value, error[:type])
      assert_equal("version", error[:field])
      assert_match(/SwarmSDK requires version: 2/, error[:message])
    end

    def test_validate_missing_swarm_name
      yaml = <<~YAML
        version: 2
        swarm:
          lead: backend
          agents:
            backend:
              description: "Backend developer"
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:missing_field, error[:type])
      assert_equal("swarm.name", error[:field])
      assert_match(/Missing 'name' field in swarm configuration/, error[:message])
    end

    def test_validate_missing_lead
      yaml = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          agents:
            backend:
              description: "Backend developer"
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:missing_field, error[:type])
      assert_equal("swarm.lead", error[:field])
      assert_match(/Missing 'lead' field in swarm configuration/, error[:message])
    end

    def test_validate_missing_agents
      yaml = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: backend
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:missing_field, error[:type])
      assert_equal("swarm.agents", error[:field])
      assert_match(/Missing 'agents' field in swarm configuration/, error[:message])
    end

    def test_validate_agent_missing_description
      yaml = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: backend
          agents:
            backend:
              model: gpt-5
              directory: .
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:missing_field, error[:type])
      assert_equal("swarm.agents.backend.description", error[:field])
      assert_equal("backend", error[:agent])
      assert_match(/Agent 'backend' missing required 'description' field/, error[:message])
    end

    def test_validate_directory_not_found
      yaml = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: backend
          agents:
            backend:
              description: "Backend developer"
              directory: /nonexistent/directory
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:directory_not_found, error[:type])
      assert_equal("swarm.agents.backend.directory", error[:field])
      assert_equal("backend", error[:agent])
      assert_match(/Directory .* for agent 'backend' does not exist/, error[:message])
    end

    def test_validate_lead_agent_not_found
      yaml = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: nonexistent
          agents:
            backend:
              description: "Backend developer"
              directory: .
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:invalid_reference, error[:type])
      assert_equal("swarm.lead", error[:field])
      assert_match(/Lead agent 'nonexistent' not found in agents/, error[:message])
    end

    def test_validate_circular_dependency
      yaml = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: a
          agents:
            a:
              description: "Agent A"
              directory: .
              delegates_to: [b]
            b:
              description: "Agent B"
              directory: .
              delegates_to: [c]
            c:
              description: "Agent C"
              directory: .
              delegates_to: [a]
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:circular_dependency, error[:type])
      assert_nil(error[:field])
      assert_match(/Circular dependency detected/, error[:message])
    end

    def test_validate_unknown_agent_in_delegates_to
      yaml = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: backend
          agents:
            backend:
              description: "Backend developer"
              directory: .
              delegates_to: [nonexistent]
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:invalid_reference, error[:type])
      assert_equal("swarm.agents.backend.delegates_to", error[:field])
      assert_equal("backend", error[:agent])
      assert_match(/Agent 'backend' has connection to unknown agent 'nonexistent'/, error[:message])
    end

    def test_validate_invalid_yaml_syntax
      yaml = "{ invalid yaml: [ unclosed"

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:syntax_error, error[:type])
      assert_nil(error[:field])
      assert_match(/Invalid YAML syntax/, error[:message])
    end

    def test_validate_file_with_valid_config
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, "config.yml")
        yaml = <<~YAML
          version: 2
          swarm:
            name: "Test Swarm"
            lead: backend
            agents:
              backend:
                description: "Backend developer"
                directory: #{dir}
        YAML
        File.write(config_path, yaml)

        errors = SwarmSDK.validate_file(config_path)

        assert_empty(errors)
      end
    end

    def test_validate_file_not_found
      errors = SwarmSDK.validate_file("/nonexistent/config.yml")

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:file_not_found, error[:type])
      assert_nil(error[:field])
      assert_match(/Configuration file not found/, error[:message])
    end

    def test_validate_file_with_invalid_config
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, "config.yml")
        yaml = <<~YAML
          version: 2
          swarm:
            name: "Test Swarm"
            lead: backend
            agents:
              backend:
                model: gpt-5
                directory: #{dir}
        YAML
        File.write(config_path, yaml)

        errors = SwarmSDK.validate_file(config_path)

        assert_equal(1, errors.size)
        error = errors.first

        assert_equal(:missing_field, error[:type])
        assert_equal("swarm.agents.backend.description", error[:field])
      end
    end

    def test_validate_agent_file_reference
      Dir.mktmpdir do |dir|
        config_path = File.join(dir, "config.yml")
        yaml = <<~YAML
          version: 2
          swarm:
            name: "Test Swarm"
            lead: backend
            agents:
              backend:
                description: "Backend developer"
                agent_file: nonexistent.md
                directory: #{dir}
        YAML
        File.write(config_path, yaml)

        errors = SwarmSDK.validate_file(config_path)

        assert_equal(1, errors.size)
        error = errors.first

        assert_equal(:file_load_error, error[:type])
        assert_equal("swarm.agents.backend.agent_file", error[:field])
        assert_equal("backend", error[:agent])
      end
    end

    def test_validate_api_version_with_incompatible_provider
      yaml = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: backend
          agents:
            backend:
              description: "Backend developer"
              model: claude-sonnet-4-5
              provider: anthropic
              api_version: v1/responses
              directory: .
      YAML

      errors = SwarmSDK.validate(yaml)

      assert_equal(1, errors.size)
      error = errors.first

      assert_equal(:invalid_value, error[:type])
      assert_equal("swarm.agents.backend.api_version", error[:field])
      assert_equal("backend", error[:agent])
      assert_match(/api_version set, but provider is/, error[:message])
    end

    def test_validate_with_custom_base_dir
      Dir.mktmpdir do |dir|
        subdir = File.join(dir, "agents")
        Dir.mkdir(subdir)

        yaml = <<~YAML
          version: 2
          swarm:
            name: "Test Swarm"
            lead: backend
            agents:
              backend:
                description: "Backend developer"
                directory: #{subdir}
        YAML

        errors = SwarmSDK.validate(yaml, base_dir: dir)

        assert_empty(errors, "Expected no errors when directory exists")
      end
    end

    def test_validate_multiple_errors
      yaml = <<~YAML
        version: 1
        swarm:
          name: "Test Swarm"
      YAML

      errors = SwarmSDK.validate(yaml)

      # Should return first error encountered during validation
      assert_equal(1, errors.size)
      # Version error comes first
      error = errors.first

      assert_equal(:invalid_value, error[:type])
      assert_equal("version", error[:field])
    end
  end
end
