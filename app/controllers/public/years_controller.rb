module Public
  # Durable landing pages for calendar years (issue #152). No index page:
  # years are an open, low-value set whose members are discoverable from the
  # sitemap and from meeting pages, so only the leaf pages exist.
  class YearsController < ApplicationController
    include PublicRecordsInCachedOrder

    EVENTS_LIMIT = 25
    MATTERS_LIMIT = 50
    INDEX_CACHE_TTL = 5.minutes

    # Legistar data for the default jurisdiction does not predate 2000, and
    # agendas are sometimes published a year ahead, so accept next year too.
    def show
      @year = Integer(params[:year], 10)
      unless Public::LandingPageEligibility.valid_year?(@year)
        head :not_found
        return
      end

      return unless stale?(etag: show_cache_version, public: true)

      @events = records_in_cached_order(cached_event_ids, event_scope)
      @matters = records_in_cached_order(cached_matter_ids, matter_scope)
      @empty = @events.empty? && @matters.empty?
    end

    private

    def show_cache_version
      @show_cache_version ||= Public::CacheVersion.year_landing(year: @year, jurisdiction: current_jurisdiction)
    end

    def year_range
      Date.new(@year, 1, 1)..Date.new(@year, 12, 31)
    end

    def event_scope
      Civic::Event.for_jurisdiction(current_jurisdiction).includes(event_items: { matter: :attachments })
    end

    def matter_scope
      Civic::Matter.for_jurisdiction(current_jurisdiction).includes(:attachments, :themes)
    end

    def cached_event_ids
      Rails.cache.fetch([ show_cache_version, "event-ids" ], expires_in: INDEX_CACHE_TTL) do
        Civic::Event
          .current_from_source
          .for_jurisdiction(current_jurisdiction)
          .where(event_date: year_range)
          .recent_first
          .limit(EVENTS_LIMIT)
          .pluck(:id)
      end
    end

    # A matter belongs to a year through either its agenda date or its
    # introduction date; matters never heard but filed in the year still show.
    def cached_matter_ids
      Rails.cache.fetch([ show_cache_version, "matter-ids" ], expires_in: INDEX_CACHE_TTL) do
        scope = Civic::Matter.for_jurisdiction(current_jurisdiction)
        scope
          .where(agenda_date: year_range)
          .or(scope.where(intro_date: year_range))
          .recent_first
          .limit(MATTERS_LIMIT)
          .pluck(:id)
      end
    end
  end
end
