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

    SITEMAP_CACHE_TTL = 5.minutes

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
      ] + landing_sitemap_urls
    end

    # Durable landing-page rows (issue #152). Only populated leaves are
    # advertised: thin (noindex) variants are excluded by construction, and
    # the /topics and /bodies hubs are included only when they have at least
    # one populated leaf to link to.
    #
    # The aggregates are cached as raw data (slugs, names, years, and
    # timestamps, never URL strings) so a cached entry is not pinned to a
    # request host, and the Last-Modified/304 path above is untouched.
    def landing_sitemap_urls
      Rails.cache.fetch([ Public::CacheVersion.landing_sitemap(jurisdiction: current_jurisdiction), "landing-urls" ], expires_in: SITEMAP_CACHE_TTL) do
        theme_updated_at = Civic::Matter
          .for_jurisdiction(current_jurisdiction)
          .joins(:themes)
          .group("civic_matter_themes.theme_slug")
          .maximum(:updated_at)

        body_event_updated_at = Public::LandingPageEligibility
          .body_scope(current_jurisdiction)
          .group(:body_name)
          .maximum(:updated_at)

        event_years = Civic::Event
          .current_from_source
          .for_jurisdiction(current_jurisdiction)
          .pluck(Arel.sql("DISTINCT EXTRACT(YEAR FROM event_date)::integer"))

        agenda_years = Civic::Matter
          .for_jurisdiction(current_jurisdiction)
          .pluck(Arel.sql("DISTINCT EXTRACT(YEAR FROM agenda_date)::integer"))

        intro_years = Civic::Matter
          .for_jurisdiction(current_jurisdiction)
          .pluck(Arel.sql("DISTINCT EXTRACT(YEAR FROM intro_date)::integer"))

        {
          theme_updated_at: theme_updated_at,
          body_event_updated_at: body_event_updated_at,
          years: (event_years + agenda_years + intro_years).compact.uniq.sort
        }
      end.then { |data| landing_sitemap_rows_for(data) }
    end

    def landing_sitemap_rows_for(data)
      rows = []

      eligible_topics = data[:theme_updated_at].select do |slug, _timestamp|
        Public::LandingPageEligibility.topic_slug?(slug, current_jurisdiction)
      end
      if eligible_topics.any?
        rows << [ topics_url, Date.current ]
        eligible_topics.each do |slug, timestamp|
          rows << [ topic_url(Civic::ThemeTaxonomy.url_slug_for(slug)), timestamp ]
        end
      end

      body_names = data[:body_event_updated_at].keys.sort
      if body_names.any?
        rows << [ bodies_url, Date.current ]
        body_names.each do |name|
          rows << [ body_url(name.parameterize), data[:body_event_updated_at][name] ]
        end
      end

      data[:years].each do |year|
        next unless Public::LandingPageEligibility.valid_year?(year)

        rows << [ year_url(year), nil ]
      end

      rows
    end
  end
end
