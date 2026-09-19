require "test_helper"

module Mcp
  class PublicApiClientTest < ActiveSupport::TestCase
    test "uses the in-process API gateway for host context" do
      jurisdiction = Civic::Jurisdiction.default
      request = ActionDispatch::TestRequest.create
      request.host = jurisdiction.primary_host

      client = PublicApiClient.new(jurisdiction:, request:, routes: Object.new)
      context = client.context

      assert_equal "civicgallery_api_context", context.fetch(:kind)
      assert_equal jurisdiction.slug, context.dig(:jurisdiction, :slug)
      assert_equal "#{request.base_url}/openapi/v1.yaml", context.fetch(:openapi_url)
    end
  end
end
