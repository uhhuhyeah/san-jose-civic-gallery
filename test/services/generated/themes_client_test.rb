require "test_helper"

module Generated
  class ThemesClientTest < ActiveSupport::TestCase
    test "keeps only known taxonomy slugs and de-duplicates" do
      client = ThemesClient.new(api_key: "test-key")
      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        {
          "usage" => { "total_tokens" => 11 },
          "choices" => [
            { "message" => { "content" => { "themes" => [ "Housing", "housing", "not_a_theme", "transportation" ] }.to_json } }
          ]
        }
      end

      response = client.call(system_prompt: "system", user_prompt: "user")

      assert_equal [ "housing", "transportation" ], response.content["themes"]
      assert_equal({ "total_tokens" => 11 }, response.usage_metadata)
    end

    test "returns an empty array when the model selects no themes" do
      client = ThemesClient.new(api_key: "test-key")
      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        { "choices" => [ { "message" => { "content" => { "themes" => [] }.to_json } } ] }
      end

      response = client.call(system_prompt: "system", user_prompt: "user")

      assert_equal [], response.content["themes"]
    end

    test "rejects a response without a themes key" do
      client = ThemesClient.new(api_key: "test-key")
      client.define_singleton_method(:post_chat_completion) do |system_prompt:, user_prompt:|
        { "choices" => [ { "message" => { "content" => { "topics" => [ "housing" ] }.to_json } } ] }
      end

      error = assert_raises(ThemesClient::RequestError) do
        client.call(system_prompt: "system", user_prompt: "user")
      end

      assert_match(/themes/, error.message)
    end

    test "raises a configuration error without an api key" do
      client = ThemesClient.new(api_key: nil)

      assert_raises(ThemesClient::ConfigurationError) do
        client.call(system_prompt: "system", user_prompt: "user")
      end
    end
  end
end
