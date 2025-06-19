# frozen_string_literal: true

require "test_helper"
require "json"
require "stringio"

class TestMcpServer < Minitest::Test
  def setup
    @stdin = StringIO.new
    @stdout = StringIO.new
    @stderr = StringIO.new
    @server = ClaudeSwarmMultiModel::Mcp::Server.new(@stdin, @stdout, @stderr)
  end

  def test_initialize_notification
    notification = capture_stdout_json do
      @server.send(:send_initialize_notification)
    end

    assert_equal "2.0", notification["jsonrpc"]
    assert_equal "notifications/initialized", notification["method"]
    assert_equal "claude-swarm-multi-model-mcp", notification["params"]["meta"]["name"]
    assert notification["params"]["meta"]["version"]
  end

  def test_handle_initialize_request
    request = {
      "id" => 1,
      "method" => "initialize",
      "params" => {
        "protocolVersion" => "1.0",
        "clientInfo" => { "name" => "test-client" }
      }
    }

    response = process_request(request)

    assert_equal 1, response["id"]
    assert_equal "1.0", response["result"]["protocolVersion"]
    assert_equal "claude-swarm-multi-model", response["result"]["serverInfo"]["name"]
    assert response["result"]["serverInfo"]["version"]
    
    capabilities = response["result"]["capabilities"]
    assert capabilities["tools"]
    assert_equal ["llm/chat"], capabilities["tools"]["listTools"]
  end

  def test_handle_tools_list_request
    request = {
      "id" => 2,
      "method" => "tools/list"
    }

    response = process_request(request)

    assert_equal 2, response["id"]
    tools = response["result"]["tools"]
    assert_equal 1, tools.size
    
    tool = tools.first
    assert_equal "llm/chat", tool["name"]
    assert_equal "Send a message to an LLM and get a response", tool["description"]
    assert tool["inputSchema"]
  end

  def test_handle_tools_call_llm_chat_success
    request = {
      "id" => 3,
      "method" => "tools/call",
      "params" => {
        "name" => "llm/chat",
        "arguments" => {
          "provider" => "mock",
          "model" => "test-model",
          "messages" => [
            { "role" => "user", "content" => "Hello" }
          ]
        }
      }
    }

    # Mock the executor
    mock_executor = Minitest::Mock.new
    mock_executor.expect(:execute, 
      { success: true, response: "Hello from mock model!" },
      ["mock", "test-model", [{ "role" => "user", "content" => "Hello" }], {}]
    )

    ClaudeSwarmMultiModel::Mcp::Executor.stub :new, mock_executor do
      response = process_request(request)

      assert_equal 3, response["id"]
      assert_equal "text", response["result"]["toolResult"]["content"][0]["type"]
      assert_equal "Hello from mock model!", response["result"]["toolResult"]["content"][0]["text"]
    end

    mock_executor.verify
  end

  def test_handle_tools_call_llm_chat_with_options
    request = {
      "id" => 4,
      "method" => "tools/call",
      "params" => {
        "name" => "llm/chat",
        "arguments" => {
          "provider" => "openai",
          "model" => "gpt-4",
          "messages" => [{ "role" => "user", "content" => "Test" }],
          "temperature" => 0.7,
          "max_tokens" => 1000
        }
      }
    }

    mock_executor = Minitest::Mock.new
    mock_executor.expect(:execute,
      { success: true, response: "Response with options" },
      ["openai", "gpt-4", [{ "role" => "user", "content" => "Test" }], 
       { "temperature" => 0.7, "max_tokens" => 1000 }]
    )

    ClaudeSwarmMultiModel::Mcp::Executor.stub :new, mock_executor do
      response = process_request(request)

      assert_equal 4, response["id"]
      assert_equal "Response with options", response["result"]["toolResult"]["content"][0]["text"]
    end

    mock_executor.verify
  end

  def test_handle_tools_call_llm_chat_error
    request = {
      "id" => 5,
      "method" => "tools/call",
      "params" => {
        "name" => "llm/chat",
        "arguments" => {
          "provider" => "failing",
          "model" => "error-model",
          "messages" => [{ "role" => "user", "content" => "Test" }]
        }
      }
    }

    mock_executor = Minitest::Mock.new
    mock_executor.expect(:execute,
      { success: false, error: "Provider not available" },
      ["failing", "error-model", [{ "role" => "user", "content" => "Test" }], {}]
    )

    ClaudeSwarmMultiModel::Mcp::Executor.stub :new, mock_executor do
      response = process_request(request)

      assert_equal 5, response["id"]
      assert response["result"]["toolResult"]["isError"]
      assert_equal "Provider not available", response["result"]["toolResult"]["content"][0]["text"]
    end

    mock_executor.verify
  end

  def test_handle_tools_call_unknown_tool
    request = {
      "id" => 6,
      "method" => "tools/call",
      "params" => {
        "name" => "unknown/tool",
        "arguments" => {}
      }
    }

    response = process_request(request)

    assert_equal 6, response["id"]
    assert response["error"]
    assert_equal -32601, response["error"]["code"]
    assert_match(/Unknown tool/, response["error"]["message"])
  end

  def test_handle_tools_call_missing_arguments
    request = {
      "id" => 7,
      "method" => "tools/call",
      "params" => {
        "name" => "llm/chat",
        "arguments" => {
          "provider" => "test",
          # Missing model and messages
        }
      }
    }

    response = process_request(request)

    assert_equal 7, response["id"]
    assert response["error"]
    assert_equal -32602, response["error"]["code"]
    assert_match(/Missing required argument/, response["error"]["message"])
  end

  def test_handle_unknown_method
    request = {
      "id" => 8,
      "method" => "unknown/method",
      "params" => {}
    }

    response = process_request(request)

    assert_equal 8, response["id"]
    assert response["error"]
    assert_equal -32601, response["error"]["code"]
    assert_equal "Method not found", response["error"]["message"]
  end

  def test_handle_invalid_json
    @stdin.string = "invalid json {]}"
    
    assert_output(nil, /Failed to parse JSON/) do
      @server.start
    end
  end

  def test_server_loop_processes_multiple_requests
    requests = [
      { "id" => 1, "method" => "initialize", "params" => { "protocolVersion" => "1.0" } },
      { "id" => 2, "method" => "tools/list" },
      { "id" => 3, "method" => "shutdown" }
    ]

    @stdin.string = requests.map { |r| JSON.generate(r) }.join("\n")
    
    responses = []
    original_puts = @stdout.method(:puts)
    @stdout.define_singleton_method(:puts) do |content|
      responses << JSON.parse(content) if content.start_with?("{")
      original_puts.call(content)
    end

    @server.start

    # Should have initialization notification + 3 responses
    assert_equal 4, responses.size
    assert_equal "notifications/initialized", responses[0]["method"]
    assert_equal 1, responses[1]["id"]
    assert_equal 2, responses[2]["id"]
    assert_equal 3, responses[3]["id"]
  end

  def test_concurrent_request_handling
    # Test that the server can handle concurrent requests properly
    request1 = {
      "id" => 1,
      "method" => "tools/call",
      "params" => {
        "name" => "llm/chat",
        "arguments" => {
          "provider" => "mock",
          "model" => "model1",
          "messages" => [{ "role" => "user", "content" => "Request 1" }]
        }
      }
    }

    request2 = {
      "id" => 2,
      "method" => "tools/call",
      "params" => {
        "name" => "llm/chat",
        "arguments" => {
          "provider" => "mock",
          "model" => "model2",
          "messages" => [{ "role" => "user", "content" => "Request 2" }]
        }
      }
    }

    mock_executor = Object.new
    def mock_executor.execute(provider, model, messages, options)
      sleep(0.1) # Simulate processing time
      { success: true, response: "Response for #{model}" }
    end

    ClaudeSwarmMultiModel::Mcp::Executor.stub :new, mock_executor do
      # Process requests in parallel threads
      threads = []
      responses = []
      
      [request1, request2].each do |request|
        threads << Thread.new do
          response = process_request(request)
          responses << response
        end
      end

      threads.each(&:join)

      assert_equal 2, responses.size
      response1 = responses.find { |r| r["id"] == 1 }
      response2 = responses.find { |r| r["id"] == 2 }

      assert_equal "Response for model1", response1["result"]["toolResult"]["content"][0]["text"]
      assert_equal "Response for model2", response2["result"]["toolResult"]["content"][0]["text"]
    end
  end

  def test_error_handling_in_request_processing
    # Test various error scenarios
    error_cases = [
      {
        request: { "id" => nil, "method" => "test" },
        error_match: /Request must have an id/
      },
      {
        request: { "id" => 1 },
        error_match: /Request must have a method/
      },
      {
        request: { "id" => 1, "method" => "tools/call" },
        error_match: /tools\/call requires params/
      }
    ]

    error_cases.each_with_index do |test_case, index|
      response = process_request(test_case[:request])
      
      if test_case[:request]["id"]
        assert_equal test_case[:request]["id"], response["id"], "Case #{index}"
        assert response["error"], "Case #{index} should have error"
        assert_match test_case[:error_match], response["error"]["message"], "Case #{index}"
      else
        # Without ID, should return generic error
        assert response["error"], "Case #{index} should have error"
      end
    end
  end

  private

  def capture_stdout_json
    @stdout.truncate(0)
    @stdout.rewind
    yield
    @stdout.rewind
    JSON.parse(@stdout.string.lines.first)
  end

  def process_request(request)
    @stdout.truncate(0)
    @stdout.rewind
    @server.send(:handle_request, request)
    @stdout.rewind
    JSON.parse(@stdout.string.lines.last)
  end
end