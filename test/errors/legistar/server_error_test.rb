require "test_helper"

module Legistar
  class ServerErrorTest < ActiveSupport::TestCase
    test "includes status code and request url in message" do
      error = Legistar::ServerError.new(status_code: 503, request_url: "https://example.com/api")
      assert_equal 503, error.status_code
      assert_equal "https://example.com/api", error.request_url
      assert_match(/503/, error.message)
      assert_match(/https:\/\/example.com\/api/, error.message)
    end
  end
end
