require "test_helper"

module Api
  module V1
    class RecordsControllerTest < ActionDispatch::IntegrationTest
      setup do
        PublicRateLimitedSearch::RATE_LIMIT_STORE.clear
        @matter = Civic::Matter.create!(legistar_matter_id: 20_901, matter_file: "26-901", title: "Library agreement")
        @attachment = @matter.all_attachments.create!(legistar_matter_attachment_id: 20_901, name: "Library report", hyperlink: "https://sanjose.legistar.com/View.ashx?M=F&ID=209")
        @attachment.extracted_texts.create!(extractor_name: "pdftotext", status: "ok", content: "Library agreement funding is available.", character_count: 38)
      end

      test "publishes host-scoped, cacheable API discovery and bounded search" do
        host! "sanjose.civicgallery.org"
        get "/api/v1/context"

        assert_response :success
        context = JSON.parse(response.body)
        assert_equal "civicgallery_api_context", context.fetch("kind")
        assert_equal "sanjose", context.dig("jurisdiction", "slug")
        assert_includes response.headers.fetch("Cache-Control"), "public"
        assert_equal "Host", response.headers.fetch("Vary")

        get "/api/v1/matters/search", params: { query: "library", limit: 1 }
        assert_response :success
        result = JSON.parse(response.body)
        assert_equal "civicgallery_matter_search_results", result.fetch("kind")
        assert_equal [ "26-901" ], result.fetch("results").pluck("matter_identifier")
      end

      test "uses safe API errors for malformed and unavailable references" do
        get "/api/v1/matters/search", params: { query: " " }
        assert_response :unprocessable_entity
        assert_equal "invalid_request", JSON.parse(response.body).dig("error", "code")

        get "/api/v1/matters/detail", params: { reference: "forged" }
        assert_response :not_found
        assert_equal "not_found", JSON.parse(response.body).dig("error", "code")
      end

      test "returns a retryable safe error when the database search exceeds its budget" do
        original_call = Public::SearchQueryTimeout.method(:call)
        Public::SearchQueryTimeout.define_singleton_method(:call) { |**| raise Public::SearchQueryTimeout::Error }

        begin
          get "/api/v1/matters/search", params: { query: "agreement" }
        ensure
          Public::SearchQueryTimeout.define_singleton_method(:call, original_call)
        end

        assert_response :service_unavailable
        assert_equal "search_timeout", JSON.parse(response.body).dig("error", "code")
      end
    end
  end
end
