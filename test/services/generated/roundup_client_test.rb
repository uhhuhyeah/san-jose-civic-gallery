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
      assert_equal [], response.content["decision_blurbs"]
      assert_equal [], response.content["highlights"]
    end

    test "normalizes highlights into stripped non-blank strings" do
      client = RoundupClient.new(api_key: "test-key")
      response_body = {
        "choices" => [
          {
            "message" => {
              "content" => {
                "headline" => "May in San Jose",
                "intro" => "Intro.",
                "storyline" => "Story.",
                "highlights" => [ "  Housing package introduced  ", "", "Transit funding debated", 42 ]
              }.to_json
            }
          }
        ]
      }

      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        response_body
      end

      response = client.call(system_prompt: "system", user_prompt: "user")

      assert_equal [ "Housing package introduced", "Transit funding debated", "42" ], response.content["highlights"]
    end

    test "temperature is configurable and warmer by default" do
      assert_in_delta 0.6, RoundupClient.new(api_key: "k").temperature, 0.001
      assert_in_delta 0.3, RoundupClient.new(api_key: "k", temperature: 0.3).temperature, 0.001
    end

    test "normalizes decision_blurbs and drops malformed entries" do
      client = RoundupClient.new(api_key: "test-key")
      response_body = {
        "choices" => [
          {
            "message" => {
              "content" => {
                "headline" => "May in San Jose",
                "intro" => "Intro.",
                "storyline" => "Story.",
                "decision_blurbs" => [
                  { "matter_file" => " 26-100 ", "blurb" => " Council passed the housing agreement. " },
                  { "matter_file" => "26-200" },                       # missing blurb -> dropped
                  { "blurb" => "No file number." },                    # missing matter_file -> dropped
                  "not a hash"                                         # wrong type -> dropped
                ]
              }.to_json
            }
          }
        ]
      }

      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        response_body
      end

      response = client.call(system_prompt: "system", user_prompt: "user")

      assert_equal(
        [ { "matter_file" => "26-100", "blurb" => "Council passed the housing agreement." } ],
        response.content["decision_blurbs"]
      )
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
