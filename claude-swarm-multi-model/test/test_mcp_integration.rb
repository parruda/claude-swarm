# frozen_string_literal: true

require "test_helper"
require "json"
require "socket"
require "timeout"

class TestMcpIntegration < Minitest::Test
  def setup
    @server_thread = nil
    @client_socket = nil
    @server_socket = nil
  end

  def teardown
    @client_socket&.close
    @server_socket&.close
    @server_thread&.kill
  end

  def test_full_mcp_session_flow
    # Create a pipe for communication
    reader, writer = IO.pipe
    client_reader, client_writer = IO.pipe
    
    # Start MCP server in a thread
    @server_thread = Thread.new do
      server = ClaudeSwarmMultiModel::Mcp::Server.new(reader, client_writer, $stderr)
      server.start
    end
    
    # Give server time to start
    sleep 0.1
    
    # Read initialization notification
    init_notification = read_json_response(client_reader)
    assert_equal "notifications/initialized", init_notification["method"]
    
    # Send initialize request
    init_request = {
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => {
        "protocolVersion" => "1.0",
        "clientInfo" => {
          "name" => "test-client",
          "version" => "1.0.0"
        }
      }
    }
    
    send_json_request(writer, init_request)
    
    # Read initialize response
    init_response = read_json_response(client_reader)
    assert_equal 1, init_response["id"]
    assert_equal "1.0", init_response["result"]["protocolVersion"]
    assert init_response["result"]["capabilities"]["tools"]
    
    # List tools
    list_tools_request = {
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/list"
    }
    
    send_json_request(writer, list_tools_request)
    
    # Read tools list response
    tools_response = read_json_response(client_reader)
    assert_equal 2, tools_response["id"]
    assert_equal 1, tools_response["result"]["tools"].size
    assert_equal "llm/chat", tools_response["result"]["tools"][0]["name"]
    
    # Call llm/chat tool
    chat_request = {
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => {
        "name" => "llm/chat",
        "arguments" => {
          "provider" => "mock",
          "model" => "test-model",
          "messages" => [
            { "role" => "user", "content" => "Hello, MCP!" }
          ]
        }
      }
    }
    
    # Mock the executor for this test
    mock_response = { success: true, response: "Hello from MCP integration test!" }
    ClaudeSwarmMultiModel::Mcp::Executor.stub :new, MockExecutor.new(mock_response) do
      send_json_request(writer, chat_request)
      
      # Read chat response
      chat_response = read_json_response(client_reader)
      assert_equal 3, chat_response["id"]
      assert_equal "text", chat_response["result"]["toolResult"]["content"][0]["type"]
      assert_equal "Hello from MCP integration test!", 
                   chat_response["result"]["toolResult"]["content"][0]["text"]
    end
    
    # Shutdown
    shutdown_request = {
      "jsonrpc" => "2.0",
      "id" => 4,
      "method" => "shutdown"
    }
    
    send_json_request(writer, shutdown_request)
    
    # Ensure server thread completes
    @server_thread.join(1)
    
  ensure
    reader&.close
    writer&.close
    client_reader&.close
    client_writer&.close
  end

  def test_concurrent_mcp_requests
    reader, writer = IO.pipe
    client_reader, client_writer = IO.pipe
    
    # Start server
    @server_thread = Thread.new do
      server = ClaudeSwarmMultiModel::Mcp::Server.new(reader, client_writer, $stderr)
      server.start
    end
    
    sleep 0.1
    
    # Read init notification
    read_json_response(client_reader)
    
    # Initialize
    send_json_request(writer, {
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => { "protocolVersion" => "1.0" }
    })
    
    read_json_response(client_reader)
    
    # Send multiple concurrent requests
    request_threads = []
    responses = Concurrent::Array.new
    
    5.times do |i|
      request_threads << Thread.new do
        request = {
          "jsonrpc" => "2.0",
          "id" => i + 10,
          "method" => "tools/call",
          "params" => {
            "name" => "llm/chat",
            "arguments" => {
              "provider" => "mock",
              "model" => "concurrent-model",
              "messages" => [
                { "role" => "user", "content" => "Request #{i}" }
              ]
            }
          }
        }
        
        ClaudeSwarmMultiModel::Mcp::Executor.stub :new, MockExecutor.new({
          success: true,
          response: "Response for request #{i}"
        }) do
          send_json_request(writer, request)
        end
      end
    end
    
    # Collect responses
    5.times do
      response = read_json_response(client_reader)
      responses << response if response["id"] >= 10
    end
    
    request_threads.each(&:join)
    
    # Verify all requests were processed
    assert_equal 5, responses.size
    response_ids = responses.map { |r| r["id"] }.sort
    assert_equal (10..14).to_a, response_ids
    
  ensure
    reader&.close
    writer&.close
    client_reader&.close
    client_writer&.close
  end

  def test_mcp_error_handling_integration
    reader, writer = IO.pipe
    client_reader, client_writer = IO.pipe
    
    @server_thread = Thread.new do
      server = ClaudeSwarmMultiModel::Mcp::Server.new(reader, client_writer, $stderr)
      server.start
    end
    
    sleep 0.1
    
    # Skip initialization
    read_json_response(client_reader)
    
    # Send malformed request
    malformed_request = {
      "jsonrpc" => "2.0",
      # Missing id
      "method" => "tools/call",
      "params" => {}
    }
    
    send_json_request(writer, malformed_request)
    
    # Should get error response
    error_response = read_json_response(client_reader)
    assert error_response["error"]
    assert_equal -32600, error_response["error"]["code"]
    
    # Send request with invalid method
    invalid_method_request = {
      "jsonrpc" => "2.0",
      "id" => 99,
      "method" => "invalid/method"
    }
    
    send_json_request(writer, invalid_method_request)
    
    # Should get method not found error
    method_error = read_json_response(client_reader)
    assert_equal 99, method_error["id"]
    assert_equal -32601, method_error["error"]["code"]
    
  ensure
    reader&.close
    writer&.close
    client_reader&.close
    client_writer&.close
  end

  def test_session_management_integration
    # Test session creation and management
    session_manager = ClaudeSwarmMultiModel::Mcp::SessionManager.new
    
    # Create a session
    session_id = session_manager.create_session("openai", "gpt-4o")
    assert session_id
    assert session_manager.session_exists?(session_id)
    
    # Get session
    session = session_manager.get_session(session_id)
    assert_equal "openai", session[:provider]
    assert_equal "gpt-4o", session[:model]
    assert_empty session[:messages]
    
    # Add messages to session
    session_manager.add_message(session_id, "user", "Hello")
    session_manager.add_message(session_id, "assistant", "Hi there!")
    
    session = session_manager.get_session(session_id)
    assert_equal 2, session[:messages].size
    assert_equal "user", session[:messages][0][:role]
    assert_equal "Hello", session[:messages][0][:content]
    
    # Clear session
    session_manager.clear_session(session_id)
    refute session_manager.session_exists?(session_id)
  end

  def test_executor_integration
    executor = ClaudeSwarmMultiModel::Mcp::Executor.new
    
    # Test with mock provider
    ENV["MOCK_API_KEY"] = "test-key"
    
    # Mock the ruby_llm gem behavior
    mock_client = MockLLMClient.new
    
    RubyLLM.stub :client, mock_client do
      result = executor.execute("mock", "test-model", [
        { "role" => "user", "content" => "Test message" }
      ], { "temperature" => 0.7 })
      
      assert result[:success]
      assert_equal "Mocked response", result[:response]
    end
  end

  private

  def send_json_request(writer, request)
    writer.puts(JSON.generate(request))
    writer.flush
  end

  def read_json_response(reader, timeout: 2)
    Timeout.timeout(timeout) do
      line = reader.gets
      return nil unless line
      JSON.parse(line.strip)
    end
  rescue Timeout::Error
    nil
  end

  class MockExecutor
    def initialize(response)
      @response = response
    end

    def execute(provider, model, messages, options)
      @response
    end
  end

  class MockLLMClient
    def chat(messages:, model:, **options)
      { 
        "choices" => [
          {
            "message" => {
              "content" => "Mocked response"
            }
          }
        ]
      }
    end
  end

  # Mock RubyLLM module for testing
  module RubyLLM
    def self.client(provider:, api_key:, **options)
      MockLLMClient.new
    end
  end
end