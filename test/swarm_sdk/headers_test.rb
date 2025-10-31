# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class HeadersTest < Minitest::Test
    def setup
      @original_api_key = ENV["OPENAI_API_KEY"]
      ENV["OPENAI_API_KEY"] = "test-key-12345"
      RubyLLM.configure do |config|
        config.openai_api_key = "test-key-12345"
      end
    end

    def teardown
      ENV["OPENAI_API_KEY"] = @original_api_key
      RubyLLM.configure do |config|
        config.openai_api_key = @original_api_key
      end
    end

    def test_ruby_dsl_headers_support
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:backend)

        agent(:backend) do
          model("gpt-5")
          description("Backend developer")
          system_prompt("You are a backend developer")
          tools(:Read, :Write)
          headers(
            "X-Request-ID" => "test-123",
            "X-User-Team" => "engineering",
          )
        end
      end

      agent_def = swarm.agent_definition(:backend)

      assert_equal({ "X-Request-ID" => "test-123", "X-User-Team" => "engineering" }, agent_def.headers)
    end

    def test_ruby_api_headers_support
      swarm = Swarm.new(name: "Test Swarm", scratchpad: Tools::Stores::ScratchpadStorage.new)

      swarm.add_agent(create_agent(
        name: :backend,
        description: "Backend developer",
        model: "gpt-5",
        system_prompt: "Test",
        headers: {
          "X-Correlation-ID" => "abc-456",
          "X-Environment" => "test",
        },
      ))

      agent_def = swarm.agent_definition(:backend)

      assert_equal({ "X-Correlation-ID" => "abc-456", "X-Environment" => "test" }, agent_def.headers)
    end

    def test_yaml_headers_support
      yaml_content = <<~YAML
        version: 2
        swarm:
          name: "Test Swarm"
          lead: backend
          agents:
            backend:
              description: "Backend developer"
              model: gpt-5
              system_prompt: "You are a backend developer"
              headers:
                X-Request-ID: test-789
                X-Priority: high
      YAML

      with_temp_config(yaml_content) do |config_path|
        swarm = Configuration.load_file(config_path).to_swarm

        agent_def = swarm.agent_definition(:backend)

        assert_equal({ "X-Request-ID" => "test-789", "X-Priority" => "high" }, agent_def.headers)
      end
    end

    def test_empty_headers_handled_gracefully
      swarm = Swarm.new(name: "Test Swarm", scratchpad: Tools::Stores::ScratchpadStorage.new)

      swarm.add_agent(create_agent(
        name: :backend,
        description: "Backend developer",
        model: "gpt-5",
        system_prompt: "Test",
        headers: {},
      ))

      agent_def = swarm.agent_definition(:backend)

      assert_empty(agent_def.headers)
    end

    def test_nil_headers_handled_gracefully
      swarm = Swarm.new(name: "Test Swarm", scratchpad: Tools::Stores::ScratchpadStorage.new)

      swarm.add_agent(create_agent(
        name: :backend,
        description: "Backend developer",
        model: "gpt-5",
        system_prompt: "Test",
        headers: nil,
      ))

      agent_def = swarm.agent_definition(:backend)

      assert_empty(agent_def.headers)
    end

    def test_headers_with_proxy_use_case
      swarm = SwarmSDK.build do
        name("Proxy Swarm")
        lead(:backend)

        agent(:backend) do
          model("gpt-5")
          provider("openai")
          base_url("https://my-proxy.com/v1")
          description("Backend developer using proxy")
          system_prompt("You are a backend developer")
          tools(:Read)
          headers(
            "X-Proxy-Route" => "premium-tier",
            "X-Tenant-ID" => "customer-123",
            "X-Region" => "us-west",
          )
        end
      end

      agent_def = swarm.agent_definition(:backend)

      assert_equal("https://my-proxy.com/v1", agent_def.base_url)
      assert_equal(
        {
          "X-Proxy-Route" => "premium-tier",
          "X-Tenant-ID" => "customer-123",
          "X-Region" => "us-west",
        },
        agent_def.headers,
      )
    end

    private

    def with_temp_config(content)
      file = Tempfile.new(["swarm", ".yml"])
      file.write(content)
      file.close

      begin
        yield file.path
      ensure
        file.unlink
      end
    end
  end
end
