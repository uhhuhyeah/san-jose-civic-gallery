module Public
  class EventsController < ApplicationController
    def index
      return unless stale?(etag: events_index_cache_version, public: true)

      @events = records_in_cached_order(cached_recent_event_ids, Civic::Event.includes(:event_items))
      featured_items = records_in_cached_order(cached_featured_item_ids, current_event_items)
      @lead_item = featured_items.first
      @watch_items = featured_items.drop(1)
      @matter_type_counts = cached_matter_type_counts
      @stats = cached_stats
    end

    def show
      @event = Civic::Event
        .includes(event_items: { matter: :attachments })
        .find(params[:id])
      @event_cache_version = Public::CacheVersion.event_show(@event)
      stale?(etag: @event_cache_version, public: true)
    end

    private

    HOMEPAGE_CACHE_TTL = 10.minutes

    def events_index_cache_version
      @events_index_cache_version ||= Public::CacheVersion.events_index
    end

    def current_event_items
      Civic::EventItem
        .current_from_source
        .includes(:event, matter: :attachments)
        .where.not(civic_matter_id: nil)
        .joins(:event)
        .merge(Civic::Event.current_from_source)
        .order("civic_events.event_date DESC, civic_event_items.agenda_sequence ASC, civic_event_items.legistar_event_item_id ASC")
    end

    def cached_recent_event_ids
      Rails.cache.fetch([ events_index_cache_version, "recent-event-ids" ], expires_in: HOMEPAGE_CACHE_TTL) do
        Civic::Event.recent_first.limit(8).pluck(:id)
      end
    end

    def cached_featured_item_ids
      Rails.cache.fetch([ events_index_cache_version, "featured-item-ids" ], expires_in: HOMEPAGE_CACHE_TTL) do
        current_event_items.limit(4).pluck(:id)
      end
    end

    def cached_matter_type_counts
      Rails.cache.fetch([ events_index_cache_version, "matter-type-counts" ], expires_in: HOMEPAGE_CACHE_TTL) do
        Civic::Matter
          .group(:matter_type_name)
          .order(Arel.sql("COUNT(*) DESC"))
          .limit(6)
          .count
      end
    end

    def cached_stats
      Rails.cache.fetch([ events_index_cache_version, "stats" ], expires_in: HOMEPAGE_CACHE_TTL) do
        {
          meetings: Civic::Event.current_from_source.count,
          agenda_items: Civic::EventItem.current_from_source.count,
          matters: Civic::Matter.count,
          attachments: Civic::MatterAttachment.current_from_source.count,
          imported_files: Civic::MatterAttachment.imported.count,
          extracted_texts: Documents::ExtractedText.where(status: "ok").count
        }
      end
    end

    def records_in_cached_order(ids, scope)
      records_by_id = scope.where(id: ids).index_by(&:id)
      ids.filter_map { |id| records_by_id[id] }
    end
  end
end
