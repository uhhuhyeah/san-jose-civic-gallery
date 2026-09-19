require "net/http"

module Mcp
  class PublicApiClient
    def initialize(base_url:, client_ip: nil)
      @base_uri = URI.parse(base_url)
      @client_ip = client_ip
    end

    def context
      get("/api/v1/context")
    end

    def search_matters(arguments)
      get("/api/v1/matters/search", arguments.slice("query", "limit"))
    end

    def matter_detail(arguments)
      get("/api/v1/matters/detail", arguments.slice("reference"))
    end

    def attachment_text_search(arguments)
      get("/api/v1/attachments/text-search", arguments.slice("attachment_reference", "query", "limit"))
    end

    private

    def get(path, query = {})
      uri = @base_uri.dup
      uri.path = path
      uri.query = query.to_query.presence
      headers = { "Accept" => "application/json" }
      headers["CF-Connecting-IP"] = @client_ip if @client_ip.present?
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.get(uri.request_uri, headers) }
      JSON.parse(response.body)
    rescue JSON::ParserError
      { "error" => { "code" => "upstream_error", "message" => "The public API returned an invalid response." } }
    end
  end
end
