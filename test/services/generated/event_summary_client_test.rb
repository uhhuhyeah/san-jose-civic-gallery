require "test_helper"

module Generated
  class EventSummaryClientTest < ActiveSupport::TestCase
    test "normalizes content shape and preserves usage metadata" do
      client = EventSummaryClient.new(api_key: "test-key")
      response_body = {
        "usage" => { "total_tokens" => 15 },
        "choices" => [
          {
            "message" => {
              "content" => {
                "summary" => " Council approved the budget. ",
                "key_topics" => [ "budget", "housing" ],
                "limitations" => [ "Limited to June meeting." ],
                "extra" => "ignored"
              }.to_json
            }
          }
        ]
      }

      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        response_body
      end

      response = client.call(system_prompt: "system", user_prompt: "user")

      assert_equal "Council approved the budget.", response.content["summary"]
      assert_equal [ "budget", "housing" ], response.content["key_topics"]
      assert_equal [ "Limited to June meeting." ], response.content["limitations"]
      assert_equal({ "total_tokens" => 15 }, response.usage_metadata)
      assert_not response.content.key?("extra")
    end

    test "coerces key_topics and limitations to arrays" do
      client = EventSummaryClient.new(api_key: "test-key")
      response_body = {
        "choices" => [
          {
            "message" => {
              "content" => {
                "summary" => "Test",
                "key_topics" => "single topic",
                "limitations" => "single limitation"
              }.to_json
            }
          }
        ]
      }

      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        response_body
      end

      response = client.call(system_prompt: "system", user_prompt: "user")

      assert_equal [ "single topic" ], response.content["key_topics"]
      assert_equal [ "single limitation" ], response.content["limitations"]
    end

    test "strips and rejects blank entries from arrays" do
      client = EventSummaryClient.new(api_key: "test-key")
      response_body = {
        "choices" => [
          {
            "message" => {
              "content" => {
                "summary" => "Test",
                "key_topics" => [ "housing", "", "  ", "budget" ],
                "limitations" => [ nil, "Short meeting" ]
              }.to_json
            }
          }
        ]
      }

      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        response_body
      end

      response = client.call(system_prompt: "system", user_prompt: "user")

      assert_equal [ "housing", "budget" ], response.content["key_topics"]
      assert_equal [ "Short meeting" ], response.content["limitations"]
    end

    test "rejects responses missing required keys" do
      client = EventSummaryClient.new(api_key: "test-key")
      response_body = {
        "choices" => [
          {
            "message" => {
              "content" => { "summary" => "Only summary" }.to_json
            }
          }
        ]
      }

      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        response_body
      end

      error = assert_raises(EventSummaryClient::RequestError) do
        client.call(system_prompt: "system", user_prompt: "user")
      end

      assert_match(/missing required keys/, error.message)
    end

    test "rejects non-object JSON from model" do
      client = EventSummaryClient.new(api_key: "test-key")
      response_body = {
        "choices" => [
          {
            "message" => {
              "content" => [ "just", "an", "array" ].to_json
            }
          }
        ]
      }

      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        response_body
      end

      error = assert_raises(EventSummaryClient::RequestError) do
        client.call(system_prompt: "system", user_prompt: "user")
      end

      assert_match(/non-object JSON/, error.message)
    end

    test "raises ConfigurationError when API key is blank" do
      client = EventSummaryClient.new(api_key: nil)
      assert_raises(EventSummaryClient::ConfigurationError) do
        client.call(system_prompt: "system", user_prompt: "user")
      end
    end

    test "default temperature is 0.1" do
      client = EventSummaryClient.new(api_key: "test-key")
      assert_in_delta 0.1, client.temperature
    end
  end
end
