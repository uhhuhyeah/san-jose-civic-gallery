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
        render json: gateway.context(base_url: request.base_url, documentation_url: api_documentation_url)
      end

      def search
        render json: gateway.search(query: params[:query], limit: params[:limit])
      rescue Public::WebMcpMatterSearch::InvalidInput => error
        render_invalid_input(error)
      end

      def detail
        render json: gateway.detail(reference: params[:reference])
      rescue Public::WebMcpMatterDetail::InvalidReference
        render_invalid_reference
      end

      def attachment_text_search
        render json: gateway.attachment_text_search(attachment_reference: params[:attachment_reference], query: params[:query], limit: params[:limit])
      rescue Public::WebMcpAttachmentTextSearch::InvalidInput => error
        render_invalid_input(error)
      rescue Public::WebMcpAttachmentTextSearch::InvalidReference
        render_invalid_reference
      end

      private

      def api_tool_request?
        params[:query].present? || params[:reference].present? || params[:attachment_reference].present?
      end

      def gateway
        @gateway ||= RecordsGateway.new(jurisdiction: current_jurisdiction, request:, routes: self)
      end
    end
  end
end
