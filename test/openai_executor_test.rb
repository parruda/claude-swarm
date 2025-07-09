# frozen_string_literal: true

require "test_helper"

module OpenAI
  class ExecutorTest < Minitest::Test
    def setup
      @tmpdir = Dir.mktmpdir
      @session_path = File.join(@tmpdir, "session-#{Time.now.to_i}")
      FileUtils.mkdir_p(@session_path)
      ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path

      # Mock OpenAI API key
      ENV["TEST_OPENAI_API_KEY"] = "test-key-123"
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
      ENV.delete("CLAUDE_SWARM_SESSION_PATH")
      ENV.delete("TEST_OPENAI_API_KEY")
    end

    def test_initialization_with_default_values
      executor = ClaudeSwarm::OpenAI::Executor.new(
        working_directory: @tmpdir,
        model: "gpt-4o",
        instance_name: "test-instance",
        instance_id: "test-123",
        openai_token_env: "TEST_OPENAI_API_KEY",
      )

      assert_equal(@tmpdir, executor.working_directory)
      assert_nil(executor.session_id)
      assert_equal(@session_path, executor.session_path)
    end

    def test_initialization_with_custom_values
      executor = ClaudeSwarm::OpenAI::Executor.new(
        working_directory: @tmpdir,
        model: "gpt-4",
        instance_name: "test-instance",
        instance_id: "test-123",
        temperature: 0.7,
        api_version: "responses",
        openai_token_env: "TEST_OPENAI_API_KEY",
        base_url: "https://custom.openai.com/v1",
      )

      assert_equal(@tmpdir, executor.working_directory)
    end

    def test_initialization_fails_without_api_key
      ENV.delete("TEST_OPENAI_API_KEY")

      assert_raises(ClaudeSwarm::OpenAI::Executor::ExecutionError) do
        ClaudeSwarm::OpenAI::Executor.new(
          working_directory: @tmpdir,
          model: "gpt-4o",
          instance_name: "test-instance",
          openai_token_env: "TEST_OPENAI_API_KEY",
        )
      end
    end

    def test_reset_session
      executor = ClaudeSwarm::OpenAI::Executor.new(
        working_directory: @tmpdir,
        model: "gpt-4o",
        instance_name: "test-instance",
        claude_session_id: "existing-session",
        openai_token_env: "TEST_OPENAI_API_KEY",
      )

      assert_predicate(executor, :has_session?)

      executor.reset_session

      refute_predicate(executor, :has_session?)
      assert_nil(executor.session_id)
    end

    def test_session_logging_setup
      ClaudeSwarm::OpenAI::Executor.new(
        working_directory: @tmpdir,
        model: "gpt-4o",
        instance_name: "test-instance",
        instance_id: "test-123",
        openai_token_env: "TEST_OPENAI_API_KEY",
      )

      # Check that log files are created
      log_file = File.join(@session_path, "session.log")
      File.join(@session_path, "session.log.json")

      assert_path_exists(log_file)

      # Verify log content
      log_content = File.read(log_file)

      assert_match(/Started OpenAI executor for instance: test-instance \(test-123\)/, log_content)
    end

    def test_mcp_config_loading
      # Create a mock MCP config file
      mcp_config_path = File.join(@tmpdir, "test.mcp.json")
      mcp_config = {
        "mcpServers" => {
          "test-server" => {
            "type" => "stdio",
            "command" => "echo",
            "args" => ["test"],
          },
        },
      }
      File.write(mcp_config_path, JSON.pretty_generate(mcp_config))

      # Mock the MCP client to prevent actual execution
      mock_mcp_client = Minitest::Mock.new
      mock_mcp_client.expect(:list_tools, [])

      MCPClient.stub(:stdio_config, lambda { |**kwargs|
        { command: kwargs[:command], name: kwargs[:name] }
      }) do
        MCPClient.stub(:create_client, mock_mcp_client) do
          executor = ClaudeSwarm::OpenAI::Executor.new(
            working_directory: @tmpdir,
            model: "gpt-4o",
            mcp_config: mcp_config_path,
            instance_name: "test-instance",
            openai_token_env: "TEST_OPENAI_API_KEY",
          )

          # Verify the executor was created successfully
          assert_instance_of(ClaudeSwarm::OpenAI::Executor, executor)
        end
      end

      mock_mcp_client.verify
    end

    def test_mcp_stdio_config_has_correct_read_timeout
      # Create MCP config with stdio server
      mcp_config_path = File.join(@tmpdir, "test-timeout.mcp.json")
      mcp_config = {
        "mcpServers" => {
          "test-stdio-server" => {
            "type" => "stdio",
            "command" => "test-cmd",
            "args" => ["arg1", "arg2"],
          },
        },
      }
      File.write(mcp_config_path, JSON.pretty_generate(mcp_config))

      # Mock MCPClient methods
      mock_mcp_client = Minitest::Mock.new
      mock_mcp_client.expect(:list_tools, [])

      # Track the config passed to stdio_config
      captured_stdio_config = nil
      MCPClient.stub(:stdio_config, lambda { |**kwargs|
        captured_stdio_config = kwargs
        { command: kwargs[:command], name: kwargs[:name], read_timeout: 1800 }
      }) do
        MCPClient.stub(:create_client, mock_mcp_client) do
          ClaudeSwarm::OpenAI::Executor.new(
            working_directory: @tmpdir,
            model: "gpt-4o",
            mcp_config: mcp_config_path,
            instance_name: "test-instance",
            openai_token_env: "TEST_OPENAI_API_KEY",
          )
        end
      end

      # Verify the correct arguments were passed
      assert_equal(["test-cmd", "arg1", "arg2"], captured_stdio_config[:command])
      assert_equal("test-stdio-server", captured_stdio_config[:name])
    end

    def test_mcp_client_created_with_1800_second_timeout
      # Create MCP config
      mcp_config_path = File.join(@tmpdir, "test-client.mcp.json")
      mcp_config = {
        "mcpServers" => {
          "server1" => {
            "type" => "stdio",
            "command" => "cmd1",
            "args" => ["--flag"],
          },
        },
      }
      File.write(mcp_config_path, JSON.pretty_generate(mcp_config))

      # Track the configs passed to create_client
      captured_mcp_configs = nil
      mock_mcp_client = Minitest::Mock.new
      mock_mcp_client.expect(:list_tools, ["tool1", "tool2"])

      MCPClient.stub(:stdio_config, lambda { |**kwargs|
        { command: kwargs[:command], name: kwargs[:name] }
      }) do
        MCPClient.stub(:create_client, lambda { |**kwargs|
          captured_mcp_configs = kwargs[:mcp_server_configs]
          mock_mcp_client
        }) do
          ClaudeSwarm::OpenAI::Executor.new(
            working_directory: @tmpdir,
            model: "gpt-4o",
            mcp_config: mcp_config_path,
            instance_name: "test-instance",
            openai_token_env: "TEST_OPENAI_API_KEY",
          )
        end
      end

      # Verify timeout was set on the config
      assert_equal(1, captured_mcp_configs.size)
      assert_equal(1800, captured_mcp_configs.first[:read_timeout])
    end

    def test_mcp_setup_with_multiple_stdio_servers
      # Create MCP config with multiple servers
      mcp_config_path = File.join(@tmpdir, "test-multi.mcp.json")
      mcp_config = {
        "mcpServers" => {
          "server1" => { "type" => "stdio", "command" => "cmd1" },
          "server2" => { "type" => "stdio", "command" => "cmd2", "args" => ["--opt"] },
          "server3" => { "type" => "stdio", "command" => "cmd3" },
        },
      }
      File.write(mcp_config_path, JSON.pretty_generate(mcp_config))

      captured_configs = []
      mock_mcp_client = Minitest::Mock.new
      mock_mcp_client.expect(:list_tools, [])

      MCPClient.stub(:stdio_config, lambda { |**kwargs|
        config = { command: kwargs[:command], name: kwargs[:name] }
        config
      }) do
        MCPClient.stub(:create_client, lambda { |**kwargs|
          captured_configs = kwargs[:mcp_server_configs]
          mock_mcp_client
        }) do
          ClaudeSwarm::OpenAI::Executor.new(
            working_directory: @tmpdir,
            model: "gpt-4o",
            mcp_config: mcp_config_path,
            instance_name: "test-instance",
            openai_token_env: "TEST_OPENAI_API_KEY",
          )
        end
      end

      # All configs should have the timeout set
      assert_equal(3, captured_configs.size)
      captured_configs.each do |config|
        assert_equal(1800, config[:read_timeout])
      end
    end

    def test_mcp_setup_handles_sse_servers
      # Create MCP config with SSE server
      mcp_config_path = File.join(@tmpdir, "test-sse.mcp.json")
      mcp_config = {
        "mcpServers" => {
          "sse-server" => {
            "type" => "sse",
            "url" => "http://example.com/sse",
          },
        },
      }
      File.write(mcp_config_path, JSON.pretty_generate(mcp_config))

      # Capture log output
      log_output = StringIO.new
      logger = Logger.new(log_output)

      Logger.stub(:new, logger) do
        ClaudeSwarm::OpenAI::Executor.new(
          working_directory: @tmpdir,
          model: "gpt-4o",
          mcp_config: mcp_config_path,
          instance_name: "test-instance",
          openai_token_env: "TEST_OPENAI_API_KEY",
        )
      end

      # Check that warning was logged
      log_content = log_output.string

      assert_match(/SSE MCP servers not yet supported/, log_content)
      assert_match(/sse-server/, log_content)
    end

    def test_mcp_setup_handles_missing_config_file
      # Try to create executor with non-existent MCP config
      executor = ClaudeSwarm::OpenAI::Executor.new(
        working_directory: @tmpdir,
        model: "gpt-4o",
        mcp_config: "/non/existent/path.json",
        instance_name: "test-instance",
        openai_token_env: "TEST_OPENAI_API_KEY",
      )

      # Should initialize without error
      assert_instance_of(ClaudeSwarm::OpenAI::Executor, executor)
    end

    def test_mcp_setup_handles_empty_mcp_servers
      # Create MCP config with empty servers
      mcp_config_path = File.join(@tmpdir, "test-empty.mcp.json")
      mcp_config = {
        "mcpServers" => {},
      }
      File.write(mcp_config_path, JSON.pretty_generate(mcp_config))

      executor = ClaudeSwarm::OpenAI::Executor.new(
        working_directory: @tmpdir,
        model: "gpt-4o",
        mcp_config: mcp_config_path,
        instance_name: "test-instance",
        openai_token_env: "TEST_OPENAI_API_KEY",
      )

      # Should initialize without creating MCP client
      assert_instance_of(ClaudeSwarm::OpenAI::Executor, executor)
    end

    def test_mcp_setup_handles_invalid_json
      # Create invalid JSON file
      mcp_config_path = File.join(@tmpdir, "test-invalid.mcp.json")
      File.write(mcp_config_path, "{ invalid json }")

      # Capture log output
      log_output = StringIO.new
      logger = Logger.new(log_output)

      executor = nil
      Logger.stub(:new, logger) do
        executor = ClaudeSwarm::OpenAI::Executor.new(
          working_directory: @tmpdir,
          model: "gpt-4o",
          mcp_config: mcp_config_path,
          instance_name: "test-instance",
          openai_token_env: "TEST_OPENAI_API_KEY",
        )
      end

      # Should handle error gracefully
      assert_instance_of(ClaudeSwarm::OpenAI::Executor, executor)
      log_content = log_output.string

      assert_match(/Failed to setup MCP client/, log_content)
    end

    def test_mcp_setup_handles_list_tools_failure
      # Create valid MCP config
      mcp_config_path = File.join(@tmpdir, "test-tools-error.mcp.json")
      mcp_config = {
        "mcpServers" => {
          "test-server" => {
            "type" => "stdio",
            "command" => "test",
          },
        },
      }
      File.write(mcp_config_path, JSON.pretty_generate(mcp_config))

      # Mock MCP client that fails on list_tools
      mock_mcp_client = Minitest::Mock.new
      def mock_mcp_client.list_tools
        raise StandardError, "Failed to connect to MCP server"
      end

      # Capture log output
      log_output = StringIO.new
      logger = Logger.new(log_output)

      executor = nil
      MCPClient.stub(:stdio_config, lambda { |**kwargs|
        { command: kwargs[:command], name: kwargs[:name] }
      }) do
        MCPClient.stub(:create_client, mock_mcp_client) do
          Logger.stub(:new, logger) do
            executor = ClaudeSwarm::OpenAI::Executor.new(
              working_directory: @tmpdir,
              model: "gpt-4o",
              mcp_config: mcp_config_path,
              instance_name: "test-instance",
              openai_token_env: "TEST_OPENAI_API_KEY",
            )
          end
        end
      end

      # Should handle error and continue
      assert_instance_of(ClaudeSwarm::OpenAI::Executor, executor)
      log_content = log_output.string

      assert_match(/Failed to load MCP tools/, log_content)
    end

    def test_mcp_mixed_server_types
      # Create MCP config with both stdio and SSE servers
      mcp_config_path = File.join(@tmpdir, "test-mixed.mcp.json")
      mcp_config = {
        "mcpServers" => {
          "stdio-server" => {
            "type" => "stdio",
            "command" => "cmd1",
            "args" => ["--flag"],
          },
          "sse-server" => {
            "type" => "sse",
            "url" => "http://example.com/sse",
          },
          "another-stdio" => {
            "type" => "stdio",
            "command" => "cmd2",
          },
        },
      }
      File.write(mcp_config_path, JSON.pretty_generate(mcp_config))

      captured_configs = []
      mock_mcp_client = Minitest::Mock.new
      mock_mcp_client.expect(:list_tools, [])

      # Capture log output for SSE warning
      log_output = StringIO.new
      logger = Logger.new(log_output)

      MCPClient.stub(:stdio_config, lambda { |**kwargs|
        { command: kwargs[:command], name: kwargs[:name] }
      }) do
        MCPClient.stub(:create_client, lambda { |**kwargs|
          captured_configs = kwargs[:mcp_server_configs]
          mock_mcp_client
        }) do
          Logger.stub(:new, logger) do
            ClaudeSwarm::OpenAI::Executor.new(
              working_directory: @tmpdir,
              model: "gpt-4o",
              mcp_config: mcp_config_path,
              instance_name: "test-instance",
              openai_token_env: "TEST_OPENAI_API_KEY",
            )
          end
        end
      end

      # Should only have stdio configs
      assert_equal(2, captured_configs.size)
      captured_configs.each do |config|
        assert_equal(1800, config[:read_timeout])
      end

      # Should warn about SSE server
      log_content = log_output.string

      assert_match(/SSE MCP servers not yet supported/, log_content)
    end

    def test_timeout_only_applied_after_stdio_config
      # This test verifies that the timeout is added after MCPClient.stdio_config returns
      mcp_config_path = File.join(@tmpdir, "test-stdio-only.mcp.json")
      mcp_config = {
        "mcpServers" => {
          "stdio-server" => {
            "type" => "stdio",
            "command" => "test",
          },
        },
      }
      File.write(mcp_config_path, JSON.pretty_generate(mcp_config))

      stdio_config_args = nil
      mock_mcp_client = Minitest::Mock.new
      mock_mcp_client.expect(:list_tools, [])

      # Capture what's passed to stdio_config
      MCPClient.stub(:stdio_config, lambda { |**kwargs|
        stdio_config_args = kwargs
        # Return a hash that simulates what stdio_config would return
        { command: kwargs[:command], name: kwargs[:name] }
      }) do
        MCPClient.stub(:create_client, lambda { |**kwargs|
          configs = kwargs[:mcp_server_configs]
          # Verify that timeout is set on the config passed to create_client
          assert_equal(1, configs.size)
          assert_equal(1800, configs.first[:read_timeout])
          mock_mcp_client
        }) do
          ClaudeSwarm::OpenAI::Executor.new(
            working_directory: @tmpdir,
            model: "gpt-4o",
            mcp_config: mcp_config_path,
            instance_name: "test-instance",
            openai_token_env: "TEST_OPENAI_API_KEY",
          )
        end
      end

      # Verify stdio_config was called without read_timeout
      assert_equal({ command: ["test"], name: "stdio-server" }, stdio_config_args)
    end

    private

    def with_mcp_stubs(stdio_config_lambda: nil, create_client_lambda: nil)
      mock_mcp_client = Minitest::Mock.new
      mock_mcp_client.expect(:list_tools, [])

      stdio_lambda = stdio_config_lambda || lambda { |**kwargs|
        { command: kwargs[:command], name: kwargs[:name] }
      }

      client_lambda = create_client_lambda || lambda { |**_kwargs|
        mock_mcp_client
      }

      MCPClient.stub(:stdio_config, stdio_lambda) do
        MCPClient.stub(:create_client, client_lambda) do
          yield mock_mcp_client
        end
      end
    end
  end
end
