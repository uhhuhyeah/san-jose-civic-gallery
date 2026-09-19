module Api
  module V1
    # The shared, in-process boundary for the public JSON API and MCP adapter.
    # It deliberately delegates only to the bounded public-record contracts;
    # neither caller receives direct model access.
    class RecordsGateway
      def initialize(jurisdiction:, request:, routes:)
        @jurisdiction = jurisdiction
        @request = request
        @routes = routes
      end

      def context(base_url:, documentation_url:)
        {
          kind: "civicgallery_api_context",
          contract_version: Public::ApiContract::VERSION,
          jurisdiction: { slug: @jurisdiction.slug, name: @jurisdiction.name, source_system: @jurisdiction.source_system_default },
          api_version: "v1",
          documentation_url:,
          openapi_url: "#{base_url}/openapi/v1.yaml",
          capabilities: Public::ApiContract.capabilities,
          source_boundaries: Public::ApiContract.source_boundaries
        }
      end

      def search(query:, limit:)
        Public::WebMcpMatterSearch.call(query:, limit:, jurisdiction: @jurisdiction, routes: @routes)
      end

      def detail(reference:)
        Public::WebMcpMatterDetail.call(reference:, jurisdiction: @jurisdiction, request: @request, routes: @routes)
      end

      def attachment_text_search(attachment_reference:, query:, limit:)
        Public::WebMcpAttachmentTextSearch.call(attachment_reference:, query:, limit:, jurisdiction: @jurisdiction, routes: @routes)
      end
    end
  end
end
