require "test_helper"

module Generated
  class RoundupClientTest < ActiveSupport::TestCase
    test "normalizes content shape and preserves usage metadata" do
      client = RoundupClient.new(api_key: "test-key")
      response_body = {
        "usage" => { "total_tokens" => 42 },
        "choices" => [
          {
            "message" => {
              "content" => {
                "headline" => " May in San Jose ",
                "intro" => "Intro text.",
                "storyline" => "Story text.",
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

      assert_equal "May in San Jose", response.content["headline"]
      assert_equal "Intro text.", response.content["intro"]
      assert_equal "Story text.", response.content["storyline"]
      assert_equal({ "total_tokens" => 42 }, response.usage_metadata)
      assert_not response.content.key?("extra")
    end

    test "rejects responses missing required keys" do
      client = RoundupClient.new(api_key: "test-key")
      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        {
          "choices" => [
            {
              "message" => {
                "content" => { "headline" => "Only headline" }.to_json
              }
            }
          ]
        }
      end

      error = assert_raises(RoundupClient::RequestError) do
        client.call(system_prompt: "system", user_prompt: "user")
      end

      assert_match(/missing required keys/, error.message)
    end

    test "raises ConfigurationError when api key is blank" do
      client = RoundupClient.new(api_key: nil)
      assert_raises(RoundupClient::ConfigurationError) do
        client.call(system_prompt: "system", user_prompt: "user")
      end
    end
  end
end
