module Api
  module V1
    class BaseController < ApplicationController
      include PublicRateLimitedSearch

      skip_before_action :verify_authenticity_token
      before_action :skip_api_session
      after_action :set_api_cache_headers

      # PublicRateLimitedSearch supplies the shared IP identity and logging
      # helpers. Its inherited index callback remains inert here, but Rails
      # requires the named action to exist on descendants.
      def index
        head :not_found
      end

      private

      def skip_api_session
        request.session_options[:skip] = true
      end

      def set_api_cache_headers
        return unless response.successful? || response.status == 304

        response.headers["Cache-Control"] = "public, max-age=300, s-maxage=7200, stale-while-revalidate=60"
        response.headers["Vary"] = "Host"
      end

      def render_invalid_input(error)
        render json: {
          error: {
            code: "invalid_request",
            message: error.message,
            documentation_url: api_documentation_url
          }
        }, status: :unprocessable_entity
      end

      def render_invalid_reference
        render json: {
          error: {
            code: "not_found",
            message: "The requested public record is unavailable.",
            documentation_url: api_documentation_url
          }
        }, status: :not_found
      end

      def render_search_timeout
        render json: {
          error: {
            code: "search_timeout",
            message: "Search is temporarily busy. Please retry with fewer or more specific keywords.",
            documentation_url: api_documentation_url
          }
        }, status: :service_unavailable
      end

      def api_documentation_url
        "#{request.base_url}/docs/api/v1"
      end
    end
  end
end
