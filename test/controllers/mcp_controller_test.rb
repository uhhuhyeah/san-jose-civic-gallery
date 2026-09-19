require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  FakeApiClient = Struct.new(:payload) do
    def context = payload
    def search_matters(_) = payload
    def matter_detail(_) = payload
    def attachment_text_search(_) = payload
  end

  setup do
    @original_factory = McpController.api_client_factory
    McpController.api_client_factory = ->(_) { FakeApiClient.new({ "kind" => "civicgallery_matter_search_results", "source_boundaries" => { "extracted_document_text" => "untrusted" } }) }
  end

  teardown do
    McpController.api_client_factory = @original_factory
  end

  test "negotiates tools and returns API payloads as MCP content" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-03-26" } }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :success
    assert_equal "2025-03-26", JSON.parse(response.body).dig("result", "protocolVersion")

    post "/mcp", params: { jsonrpc: "2.0", id: 2, method: "tools/list" }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    tools = JSON.parse(response.body).dig("result", "tools")
    assert_equal [ "get_page_context", "search_matters", "get_matter_detail", "search_attachment_text" ], tools.pluck("name")

    post "/mcp", params: { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "search_matters", arguments: { query: "library" } } }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    result = JSON.parse(response.body).fetch("result")
    assert_equal false, result.fetch("isError")
    assert_equal "civicgallery_matter_search_results", JSON.parse(result.dig("content", 0, "text")).fetch("kind")
  end

  test "rejects cross-origin browser requests" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: { "CONTENT_TYPE" => "application/json", "ORIGIN" => "https://attacker.example" }
    assert_response :forbidden
  end

  test "accepts mixed JSON-RPC batches and acknowledges notifications without a body" do
    post "/mcp", params: [
      { jsonrpc: "2.0", method: "notifications/cancelled", params: { requestId: 9 } },
      { jsonrpc: "2.0", id: 4, method: "tools/list" }
    ].to_json, headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal 1, response_body.length
    assert_equal 4, response_body.first.fetch("id")
    assert_equal "search_matters", response_body.first.dig("result", "tools", 1, "name")

    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/cancelled", params: { requestId: 9 } }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :accepted
    assert_empty response.body
  end

  test "returns invalid params for a non-object tool arguments value" do
    post "/mcp", params: { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "search_matters", arguments: "bad" } }.to_json, headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :success
    error = JSON.parse(response.body).fetch("error")
    assert_equal(-32_602, error.fetch("code"))
    assert_equal "Tool arguments must be an object.", error.fetch("message")
  end

  test "returns a retryable tool error when the search database budget is exceeded" do
    timeout_client = Object.new
    timeout_client.define_singleton_method(:search_matters) { |_| raise Public::SearchQueryTimeout::Error }
    server = Mcp::Server.new(api_client: timeout_client)

    response = server.respond({
      "jsonrpc" => "2.0", "id" => 5, "method" => "tools/call",
      "params" => { "name" => "search_matters", "arguments" => { "query" => "agreement" } }
    })

    assert_equal true, response.dig(:result, :isError)
    assert_equal "search_timeout", JSON.parse(response.dig(:result, :content, 0, :text)).dig("error", "code")
  end
end
