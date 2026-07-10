require "test_helper"

module Search
  class EmbeddingClientTest < ActiveSupport::TestCase
    test "normalizes embedding response and preserves usage metadata" do
      client = EmbeddingClient.new(api_key: "test-key")
      response_body = {
        "data" => [
          { "embedding" => [ 0.001, -0.002, 0.003 ], "index" => 0 }
        ],
        "model" => "text-embedding-3-small",
        "usage" => { "prompt_tokens" => 5, "total_tokens" => 5 }
      }

      client.define_singleton_method(:post_embedding) do |_input|
        response_body
      end

      response = client.embed("Test input")

      assert_equal [ 0.001, -0.002, 0.003 ], response.vector
      assert_equal "text-embedding-3-small", response.model_name
      assert_equal({ "prompt_tokens" => 5, "total_tokens" => 5 }, response.usage_metadata)
    end

    test "raises ConfigurationError without api_key" do
      client = EmbeddingClient.new(api_key: nil)

      error = assert_raises(EmbeddingClient::ConfigurationError) do
        client.embed("test")
      end

      assert_match(/SEMANTIC_SEARCH_API_KEY/, error.message)
    end

    test "raises RequestError when embedding is missing from response" do
      client = EmbeddingClient.new(api_key: "test-key")
      client.define_singleton_method(:post_embedding) do |_input|
        { "data" => [ {} ], "model" => "test", "usage" => {} }
      end

      error = assert_raises(EmbeddingClient::RequestError) do
        client.embed("test")
      end

      assert_match(/missing data\[0\]\.embedding/, error.message)
    end

    test "raises RequestError on invalid JSON response" do
      client = EmbeddingClient.new(api_key: "test-key")
      client.define_singleton_method(:perform_http_request) do |*, **|
        Struct.new(:code, :body).new("200", "not json")
      end

      error = assert_raises(EmbeddingClient::RequestError) do
        client.embed("test")
      end

      assert_match(/invalid JSON/, error.message)
    end

    test "exposes model_name and dimensions through accessors" do
      client = EmbeddingClient.new(
        api_key: "test-key",
        model_name: "custom-model",
        dimensions: 768
      )

      assert_equal "custom-model", client.model_name
      assert_equal 768, client.dimensions
    end
  end
end
