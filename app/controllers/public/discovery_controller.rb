module Public
  # Machine-readable discovery endpoints for search crawlers and LLM-oriented
  # clients. Responses are host-scoped so sanjose.civicgallery.org and
  # sjusd.civicgallery.org each advertise only their own public records.
  class DiscoveryController < ApplicationController
    RECORD_LIMIT = 20_000

    def robots
      render plain: robots_body, content_type: "text/plain"
    end

    def llms
      render formats: :text, content_type: "text/plain"
    end

    def sitemap
      @static_urls = static_sitemap_urls
      @events = Civic::Event.current_from_source
        .for_jurisdiction(current_jurisdiction)
        .recent_first
        .limit(RECORD_LIMIT)
      @matters = Civic::Matter
        .for_jurisdiction(current_jurisdiction)
        .recent_first
        .limit(RECORD_LIMIT)

      render formats: :xml
    end

    private

    def robots_body
      <<~ROBOTS
        User-agent: *
        Allow: /
        Disallow: /jobs
        Disallow: /up

        Sitemap: #{sitemap_url}
        # LLM guide: #{llms_url}
      ROBOTS
    end

    def static_sitemap_urls
      [
        [ root_url, Date.current ],
        [ public_meetings_url, Civic::Event.current_from_source.for_jurisdiction(current_jurisdiction).maximum(:updated_at) ],
        [ public_matters_url, Civic::Matter.for_jurisdiction(current_jurisdiction).maximum(:updated_at) ],
        [ data_url, Date.current ],
        [ glossary_url, Date.current ],
        [ llms_url, Date.current ]
      ]
    end
  end
end
