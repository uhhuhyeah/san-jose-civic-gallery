require "test_helper"

module Generated
  class SummaryClientTest < ActiveSupport::TestCase
    test "normalizes generated content shape and preserves usage metadata" do
      client = SummaryClient.new(api_key: "test-key")
      response_body = {
        "usage" => { "prompt_tokens" => 12, "completion_tokens" => 8, "total_tokens" => 20 },
        "choices" => [
          {
            "message" => {
              "content" => {
                "summary" => " Appears to be a draft agreement. ",
                "key_points" => "Compensation increases.",
                "limitations" => "Specific expiration dates are blank.",
                "document_status" => "DRAFT",
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

      assert_equal "Appears to be a draft agreement.", response.content["summary"]
      assert_equal [ "Compensation increases." ], response.content["key_points"]
      assert_equal [ "Specific expiration dates are blank." ], response.content["limitations"]
      assert_equal "draft", response.content["document_status"]
      assert_equal({ "prompt_tokens" => 12, "completion_tokens" => 8, "total_tokens" => 20 }, response.usage_metadata)
      assert_not response.content.key?("extra")
    end

    test "rejects responses missing required keys" do
      client = SummaryClient.new(api_key: "test-key")
      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        {
          "choices" => [
            {
              "message" => {
                "content" => { "summary" => "Short" }.to_json
              }
            }
          ]
        }
      end

      error = assert_raises(SummaryClient::RequestError) do
        client.call(system_prompt: "system", user_prompt: "user")
      end

      assert_match(/missing required keys/, error.message)
    end
  end
end
