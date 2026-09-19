module Api
  module V1
    class RecordsController < BaseController
      rate_limit to: PublicRateLimitedSearch::SEARCH_RATE_LIMIT,
                 within: PublicRateLimitedSearch::SEARCH_RATE_WINDOW,
                 only: [ :search, :detail, :attachment_text_search ],
                 if: :api_tool_request?,
                 by: :rate_limit_identity,
                 with: :log_search_rate_limit_exceeded,
                 store: PublicRateLimitedSearch::RATE_LIMIT_STORE

      def context
        render json: {
          kind: "civicgallery_api_context",
          contract_version: "1.0",
          jurisdiction: jurisdiction_context,
          api_version: "v1",
          documentation_url: api_documentation_url,
          openapi_url: "#{request.base_url}/openapi/v1.yaml",
          capabilities: [
            { name: "search_matters", path: "/api/v1/matters/search", method: "GET", read_only: true },
            { name: "get_matter_detail", path: "/api/v1/matters/detail", method: "GET", read_only: true },
            { name: "search_attachment_text", path: "/api/v1/attachments/text-search", method: "GET", read_only: true }
          ],
          source_boundaries: Public::ApiContract.source_boundaries
        }
      end

      def search
        render json: Public::WebMcpMatterSearch.call(query: params[:query], limit: params[:limit], jurisdiction: current_jurisdiction, routes: self)
      rescue Public::WebMcpMatterSearch::InvalidInput => error
        render_invalid_input(error)
      end

      def detail
        render json: Public::WebMcpMatterDetail.call(reference: params[:reference], jurisdiction: current_jurisdiction, request: request, routes: self)
      rescue Public::WebMcpMatterDetail::InvalidReference
        render_invalid_reference
      end

      def attachment_text_search
        render json: Public::WebMcpAttachmentTextSearch.call(attachment_reference: params[:attachment_reference], query: params[:query], limit: params[:limit], jurisdiction: current_jurisdiction, routes: self)
      rescue Public::WebMcpAttachmentTextSearch::InvalidInput => error
        render_invalid_input(error)
      rescue Public::WebMcpAttachmentTextSearch::InvalidReference
        render_invalid_reference
      end

      private

      def api_tool_request?
        params[:query].present? || params[:reference].present? || params[:attachment_reference].present?
      end

      def jurisdiction_context
        { slug: current_jurisdiction.slug, name: current_jurisdiction.name, source_system: current_jurisdiction.source_system_default }
      end
    end
  end
end
