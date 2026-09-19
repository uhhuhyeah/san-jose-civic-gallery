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
end
