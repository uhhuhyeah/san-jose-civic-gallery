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
      # Events with no ingested agenda items render only template scaffolding
      # and are noindex'd at the page level; advertising them in the sitemap
      # would just send crawlers to URLs we're telling them to skip. Once
      # ingestion fills an event, it re-enters the sitemap on the next render.
      events = Civic::Event.current_from_source.with_agenda_items.for_jurisdiction(current_jurisdiction)
      matters = Civic::Matter.for_jurisdiction(current_jurisdiction)

      # Crawlers poll this endpoint repeatedly. Serve a Last-Modified so an
      # unchanged sitemap returns 304 without building up to 40k URL rows, and
      # an expiry so intermediaries can hold it briefly.
      last_modified = [ events.maximum(:updated_at), matters.maximum(:updated_at) ].compact.max
      expires_in 1.hour, public: true
      return unless stale?(last_modified: last_modified, public: true)

      @static_urls = static_sitemap_urls
      @events = events.recent_first.limit(RECORD_LIMIT)
      @matters = matters.recent_first.limit(RECORD_LIMIT)

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
