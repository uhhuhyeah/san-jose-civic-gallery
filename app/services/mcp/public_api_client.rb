module Mcp
  class PublicApiClient
    def initialize(jurisdiction:, request:, routes:)
      @gateway = Api::V1::RecordsGateway.new(jurisdiction:, request:, routes:)
      @base_url = request.base_url
    end

    def context
      @gateway.context(base_url: @base_url, documentation_url: "#{@base_url}/docs/api/v1")
    end

    def search_matters(arguments)
      @gateway.search(query: arguments["query"], limit: arguments["limit"])
    end

    def matter_detail(arguments)
      @gateway.detail(reference: arguments["reference"])
    end

    def attachment_text_search(arguments)
      @gateway.attachment_text_search(attachment_reference: arguments["attachment_reference"], query: arguments["query"], limit: arguments["limit"])
    end
  end
end
