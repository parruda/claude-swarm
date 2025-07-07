# frozen_string_literal: true

require "test_helper"

class OpenAIIntegrationTest < Minitest::Test
  def test_chat_completion_simple_message
    # Create a logger that accepts anything
    mock_logger = Minitest::Mock.new
    def mock_logger.info(*args); end
    def mock_logger.error(*args); end
    def mock_logger.log(*args); end

    mock_mcp_client = Minitest::Mock.new
    mock_openai_client = Minitest::Mock.new

    api = ClaudeSwarm::OpenAIChatCompletion.new(
      openai_client: mock_openai_client,
      mcp_client: mock_mcp_client,
      available_tools: [],
      logger: mock_logger,
      instance_name: "test",
      model: "gpt-4o",
    )

    # Mock the chat call
    mock_response = {
      "choices" => [{
        "message" => {
          "role" => "assistant",
          "content" => "Hello world!",
        },
      }],
    }

    mock_openai_client.expect(:chat, mock_response) do |params|
      params[:parameters][:messages].last[:content] == "Hello"
    end

    result = api.execute("Hello")

    assert_equal("Hello world!", result)

    mock_openai_client.verify
  end

  def test_responses_api_simple_message
    # Create a logger that accepts anything
    mock_logger = Minitest::Mock.new
    def mock_logger.info(*args); end
    def mock_logger.error(*args); end
    def mock_logger.log(*args); end

    mock_mcp_client = Minitest::Mock.new
    mock_openai_client = Minitest::Mock.new
    mock_responses_api = Minitest::Mock.new

    # Set up OpenAI client to return responses API
    mock_openai_client.expect(:responses, mock_responses_api)

    api = ClaudeSwarm::OpenAIResponses.new(
      openai_client: mock_openai_client,
      mcp_client: mock_mcp_client,
      available_tools: [],
      logger: mock_logger,
      instance_name: "test",
      model: "o3-pro",
    )

    # Mock the create call
    mock_response = {
      "id" => "resp_123",
      "output" => [{
        "type" => "message",
        "content" => [{
          "type" => "text",
          "text" => "Hello from responses API!",
        }],
      }],
    }

    mock_responses_api.expect(:create, mock_response) do |params|
      params[:parameters][:input] == "Hello"
    end

    result = api.execute("Hello")

    assert_equal("Hello from responses API!", result)

    mock_openai_client.verify
    mock_responses_api.verify
  end

  def test_chat_completion_with_tools
    # Create a flexible logger
    mock_logger = Minitest::Mock.new
    def mock_logger.info(*args); end
    def mock_logger.error(*args); end
    def mock_logger.log(*args); end
    def mock_logger.debug(*args); end

    mock_mcp_client = Minitest::Mock.new
    mock_openai_client = Minitest::Mock.new

    # Create a mock tool
    mock_tool = Struct.new(:name, :description, :schema).new(
      "TestTool",
      "A test tool",
      { "type" => "object", "properties" => {} },
    )

    api = ClaudeSwarm::OpenAIChatCompletion.new(
      openai_client: mock_openai_client,
      mcp_client: mock_mcp_client,
      available_tools: [mock_tool],
      logger: mock_logger,
      instance_name: "test",
      model: "gpt-4o",
    )

    # Mock MCP client's to_openai_tools method (called multiple times)
    2.times do
      mock_mcp_client.expect(:to_openai_tools, [{
        type: "function",
        function: {
          name: "TestTool",
          description: "A test tool",
          parameters: { "type" => "object", "properties" => {} },
        },
      }])
    end

    # First response with tool call
    first_response = {
      "choices" => [{
        "message" => {
          "role" => "assistant",
          "tool_calls" => [{
            "id" => "call_123",
            "type" => "function",
            "function" => {
              "name" => "TestTool",
              "arguments" => "{}",
            },
          }],
        },
      }],
    }

    mock_openai_client.expect(:chat, first_response) do |params|
      params[:parameters][:tools]&.any?
    end

    # Mock tool execution
    mock_mcp_client.expect(
      :call_tool,
      {
        "content" => [{ "type" => "text", "text" => "Tool result" }],
      },
      ["TestTool", {}],
    )

    # Second response after tool execution
    second_response = {
      "choices" => [{
        "message" => {
          "role" => "assistant",
          "content" => "Tool executed successfully",
        },
      }],
    }

    mock_openai_client.expect(:chat, second_response) do |params|
      params[:parameters][:messages].any? { |m| m[:role] == "tool" }
    end

    result = api.execute("Use the test tool")

    assert_equal("Tool executed successfully", result)

    mock_openai_client.verify
    mock_mcp_client.verify
  end

  def test_responses_api_with_tools
    # Create a flexible logger
    mock_logger = Minitest::Mock.new
    def mock_logger.info(*args); end
    def mock_logger.error(*args); end
    def mock_logger.log(*args); end
    def mock_logger.debug(*args); end

    mock_mcp_client = Minitest::Mock.new
    mock_openai_client = Minitest::Mock.new
    mock_responses_api = Minitest::Mock.new

    # Set up OpenAI client to return responses API (called twice - once in init, once per API call)
    2.times do
      mock_openai_client.expect(:responses, mock_responses_api)
    end

    # Create a mock tool
    mock_tool = Struct.new(:name, :description, :schema).new(
      "TestTool",
      "A test tool",
      { "type" => "object", "properties" => {} },
    )

    api = ClaudeSwarm::OpenAIResponses.new(
      openai_client: mock_openai_client,
      mcp_client: mock_mcp_client,
      available_tools: [mock_tool],
      logger: mock_logger,
      instance_name: "test",
      model: "o3-pro",
    )

    # First response with function call
    first_response = {
      "id" => "resp_1",
      "output" => [{
        "type" => "function_call",
        "name" => "TestTool",
        "arguments" => "{}",
        "call_id" => "call_123",
        "id" => "fc_123",
      }],
    }

    mock_responses_api.expect(:create, first_response) do |params|
      params[:parameters][:tools]&.any?
    end

    # Mock tool execution
    mock_mcp_client.expect(
      :call_tool,
      {
        "content" => [{ "type" => "text", "text" => "Tool result" }],
      },
      ["TestTool", {}],
    )

    # Second response after tool execution
    second_response = {
      "id" => "resp_2",
      "output" => [{
        "type" => "message",
        "content" => [{
          "type" => "text",
          "text" => "Tool executed via responses API",
        }],
      }],
      "previous_response_id" => "resp_1",
    }

    mock_responses_api.expect(:create, second_response) do |actual_params|
      # Just check that it has the right structure
      actual_params[:parameters][:input].is_a?(Array) &&
        actual_params[:parameters][:previous_response_id] == "resp_1"
    end

    result = api.execute("Use the test tool")

    assert_equal("Tool executed via responses API", result)

    mock_openai_client.verify
    mock_responses_api.verify
    mock_mcp_client.verify
  end
end
