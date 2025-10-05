# frozen_string_literal: true

require "test_helper"

class ConfigurationOpenaiResponsesApiTest < Minitest::Test
  def with_openai_config_file(instances_config)
    Dir.mktmpdir do |tmpdir|
      instances_yaml = instances_config.map do |name, config|
        lines = ["    #{name}:"]
        config.each do |key, value|
          # Handle array values differently
          lines << if value.is_a?(Array)
            "      #{key}: [#{value.join(", ")}]"
          else
            "      #{key}: #{value}"
          end
        end
        lines.join("\n")
      end.join("\n")

      yaml_content = <<~YAML
        version: 1
        swarm:
          name: "Test Swarm"
          main: lead
          instances:
        #{instances_yaml}
      YAML

      config_file = File.join(tmpdir, "claude-swarm.yml")
      File.write(config_file, yaml_content)
      yield config_file
    end
  end

  def with_stubbed_openai_version(version)
    # Store original VERSION if OpenAI is loaded
    original_version = ::OpenAI::VERSION if Object.const_defined?(:OpenAI) && ::OpenAI.const_defined?(:VERSION)

    # Ensure OpenAI module exists
    unless Object.const_defined?(:OpenAI)
      Object.const_set(:OpenAI, Module.new)
    end

    # Set the version
    ::OpenAI.send(:remove_const, :VERSION) if ::OpenAI.const_defined?(:VERSION)
    ::OpenAI.const_set(:VERSION, version)

    yield
  ensure
    # Restore original state
    if original_version
      ::OpenAI.send(:remove_const, :VERSION) if ::OpenAI.const_defined?(:VERSION)
      ::OpenAI.const_set(:VERSION, original_version)
    elsif Object.const_defined?(:OpenAI) && !defined?(original_version)
      Object.send(:remove_const, :OpenAI)
    end
  end

  def test_validates_openai_responses_api_requires_version_8_or_higher
    instances = {
      "lead" => {
        "description" => "Lead instance",
        "prompt" => "Test prompt",
      },
      "backend" => {
        "description" => "Backend with responses API",
        "provider" => "openai",
        "model" => "gpt-4",
        "api_version" => "responses",
        "openai_token_env" => "TEST_OPENAI_KEY",
      },
    }

    ENV["TEST_OPENAI_KEY"] = "test-key"

    with_openai_config_file(instances) do |config_path|
      # Test with old version - should raise error
      with_stubbed_openai_version("7.5.0") do
        error = assert_error_message(ClaudeSwarm::Error, /requires ruby-openai >= 8.0/) do
          ClaudeSwarm::Configuration.new(config_path, options: { prompt: "test" })
        end
        assert_match(/Instances backend use OpenAI provider/, error.message)
        assert_match(/Current version is 7.5.0/, error.message)
      end

      # Test with exact version 8.0.0 - should pass
      with_stubbed_openai_version("8.0.0") do
        config = ClaudeSwarm::Configuration.new(config_path, options: { prompt: "test" })

        assert_equal("Test Swarm", config.swarm_name)
      end

      # Test with higher version - should pass
      with_stubbed_openai_version("8.5.0") do
        config = ClaudeSwarm::Configuration.new(config_path, options: { prompt: "test" })

        assert_equal("Test Swarm", config.swarm_name)
      end
    end
  ensure
    ENV.delete("TEST_OPENAI_KEY")
  end

  def test_multiple_instances_with_responses_api_lists_all_in_error
    instances = {
      "lead" => {
        "description" => "Lead instance",
        "prompt" => "Test prompt",
      },
      "frontend" => {
        "description" => "Frontend with responses API",
        "provider" => "openai",
        "model" => "gpt-4",
        "api_version" => "responses",
        "openai_token_env" => "TEST_OPENAI_KEY",
      },
      "backend" => {
        "description" => "Backend with responses API",
        "provider" => "openai",
        "model" => "gpt-3.5-turbo",
        "api_version" => "responses",
        "openai_token_env" => "TEST_OPENAI_KEY",
      },
      "database" => {
        "description" => "Database with chat API",
        "provider" => "openai",
        "model" => "gpt-4",
        "api_version" => "chat_completion",
        "openai_token_env" => "TEST_OPENAI_KEY",
      },
    }

    ENV["TEST_OPENAI_KEY"] = "test-key"

    with_openai_config_file(instances) do |config_path|
      with_stubbed_openai_version("6.0.0") do
        error = assert_error_message(ClaudeSwarm::Error, /requires ruby-openai >= 8.0/) do
          ClaudeSwarm::Configuration.new(config_path, options: { prompt: "test" })
        end
        # Should list both frontend and backend, but not database
        assert_match(/Instances frontend, backend use OpenAI provider/, error.message)
        assert_match(/Current version is 6.0.0/, error.message)
      end
    end
  ensure
    ENV.delete("TEST_OPENAI_KEY")
  end

  def test_chat_completion_api_does_not_require_version_check
    instances = {
      "lead" => {
        "description" => "Lead instance",
        "prompt" => "Test prompt",
      },
      "backend" => {
        "description" => "Backend with chat API",
        "provider" => "openai",
        "model" => "gpt-4",
        "api_version" => "chat_completion",
        "openai_token_env" => "TEST_OPENAI_KEY",
      },
    }

    ENV["TEST_OPENAI_KEY"] = "test-key"

    with_openai_config_file(instances) do |config_path|
      # Should pass even with old version since it's using chat_completion
      with_stubbed_openai_version("6.0.0") do
        config = ClaudeSwarm::Configuration.new(config_path, options: { prompt: "test" })

        assert_equal("Test Swarm", config.swarm_name)
        assert_equal("chat_completion", config.instances["backend"][:api_version])
      end
    end
  ensure
    ENV.delete("TEST_OPENAI_KEY")
  end

  def test_default_api_version_is_chat_completion
    instances = {
      "lead" => {
        "description" => "Lead instance",
        "prompt" => "Test prompt",
      },
      "backend" => {
        "description" => "Backend without explicit API version",
        "provider" => "openai",
        "model" => "gpt-4",
        "openai_token_env" => "TEST_OPENAI_KEY",
      },
    }

    ENV["TEST_OPENAI_KEY"] = "test-key"

    with_openai_config_file(instances) do |config_path|
      # Should default to chat_completion and not require version check
      with_stubbed_openai_version("6.0.0") do
        config = ClaudeSwarm::Configuration.new(config_path, options: { prompt: "test" })

        assert_equal("Test Swarm", config.swarm_name)
        assert_equal("chat_completion", config.instances["backend"][:api_version])
      end
    end
  ensure
    ENV.delete("TEST_OPENAI_KEY")
  end

  def test_claude_instances_are_not_affected_by_openai_validation
    instances = {
      "lead" => {
        "description" => "Lead instance",
        "prompt" => "Test prompt",
      },
      "claude_backend" => {
        "description" => "Claude backend",
        "provider" => "claude",
        "model" => "opus",
      },
      "openai_backend" => {
        "description" => "OpenAI backend with responses API",
        "provider" => "openai",
        "model" => "gpt-4",
        "api_version" => "responses",
        "openai_token_env" => "TEST_OPENAI_KEY",
      },
    }

    ENV["TEST_OPENAI_KEY"] = "test-key"

    with_openai_config_file(instances) do |config_path|
      with_stubbed_openai_version("7.0.0") do
        error = assert_error_message(ClaudeSwarm::Error, /requires ruby-openai >= 8.0/) do
          ClaudeSwarm::Configuration.new(config_path, options: { prompt: "test" })
        end
        # Should only mention the OpenAI instance
        assert_match(/Instances openai_backend use OpenAI provider/, error.message)
        refute_match(/claude_backend/, error.message)
      end
    end
  ensure
    ENV.delete("TEST_OPENAI_KEY")
  end

  def test_handles_missing_openai_gem_gracefully
    instances = {
      "lead" => {
        "description" => "Lead instance",
        "prompt" => "Test prompt",
      },
      "backend" => {
        "description" => "Backend with responses API",
        "provider" => "openai",
        "model" => "gpt-4",
        "api_version" => "responses",
        "openai_token_env" => "TEST_OPENAI_KEY",
      },
    }

    ENV["TEST_OPENAI_KEY"] = "test-key"

    with_openai_config_file(instances) do |config_path|
      # Store original state
      openai_was_defined = Object.const_defined?(:OpenAI)
      openai_module = ::OpenAI if openai_was_defined

      # Create a custom configuration that mocks the LoadError
      config_instance = nil

      # Temporarily stub require to raise LoadError
      Kernel.stub(:require, ->(lib) do
        if lib == "openai/version"
          # Remove OpenAI constant when require is called
          Object.send(:remove_const, :OpenAI) if Object.const_defined?(:OpenAI)
          raise LoadError, "cannot load such file -- #{lib}"
        end
        true
      end) do
        # Should not raise error when ruby-openai is not installed
        config_instance = ClaudeSwarm::Configuration.new(config_path, options: { prompt: "test" })
      end

      assert_equal("Test Swarm", config_instance.swarm_name)

      # Restore OpenAI if it was originally defined
      Object.const_set(:OpenAI, openai_module) if openai_was_defined && !Object.const_defined?(:OpenAI)
    end
  ensure
    ENV.delete("TEST_OPENAI_KEY")
  end

  def test_no_openai_instances_skips_validation
    instances = {
      "lead" => {
        "description" => "Lead instance",
      },
      "backend" => {
        "description" => "Backend instance",
        "provider" => "claude",
        "model" => "opus",
      },
    }

    with_openai_config_file(instances) do |config_path|
      # Should not even check OpenAI version when no OpenAI instances
      config = ClaudeSwarm::Configuration.new(config_path)

      assert_equal("Test Swarm", config.swarm_name)
    end
  end
end
