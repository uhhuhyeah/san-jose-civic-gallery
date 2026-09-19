class McpController < ApplicationController
  include PublicRateLimitedSearch

  skip_before_action :verify_authenticity_token
  before_action :skip_mcp_session
  before_action :reject_untrusted_origin

  class_attribute :api_client_factory, default: ->(request) { Mcp::PublicApiClient.new(base_url: request.base_url, client_ip: request.get_header("HTTP_CF_CONNECTING_IP").presence || request.remote_ip) }

  rate_limit to: PublicRateLimitedSearch::SEARCH_RATE_LIMIT,
             within: PublicRateLimitedSearch::SEARCH_RATE_WINDOW,
             only: :show,
             if: :mcp_post?,
             by: :rate_limit_identity,
             with: :log_search_rate_limit_exceeded,
             store: PublicRateLimitedSearch::RATE_LIMIT_STORE

  def show
    return head :method_not_allowed unless request.post?

    response = Mcp::Server.new(api_client: api_client_factory.call(request)).respond(parsed_request)
    return head response.fetch(:http_status) if response.key?(:http_status)

    render json: response, status: response.fetch(:http_status, :ok)
  rescue JSON::ParserError
    render json: Mcp::Server.invalid_request("Request body must be valid JSON."), status: :bad_request
  end

  # PublicRateLimitedSearch also registers an index-only callback. This inert
  # action makes that inherited callback valid without exposing a route.
  def index
    head :not_found
  end

  private

  def parsed_request
    JSON.parse(request.raw_post)
  end

  def mcp_post?
    request.post?
  end

  def skip_mcp_session
    request.session_options[:skip] = true
  end

  # Remote MCP clients normally omit Origin. A browser-originated request must
  # be same-origin; accepting arbitrary origins would expose the public tool
  # surface to DNS-rebinding attacks.
  def reject_untrusted_origin
    origin = request.headers["Origin"].presence
    return unless origin
    return if origin == request.base_url

    render json: { error: "origin is not allowed" }, status: :forbidden
  end
end
