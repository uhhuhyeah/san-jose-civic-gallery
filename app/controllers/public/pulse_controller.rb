module Public
  # Unlinked work-in-progress candidate homepage for the Pulse theme trends.
  # Reachable only by direct URL (/pulse-v2) and marked noindex, so it is not in
  # nav or search while it is iterated on. It composes the theme Pulse with the
  # existing homepage furniture (featured item, recent meetings, record counts);
  # on promotion this controller's data loading is consolidated with
  # EventsController#index. See docs/pulse.md.
  class PulseController < ApplicationController
    WINDOW = Public::ThemePulse::DEFAULT_WINDOW
    HEATING_UP_LIMIT = 6
    TOP_THEMES_LIMIT = 8
    CACHE_TTL = 10.minutes

    def show
      @body_name = params[:body_name].to_s.strip
      @as_of = Date.current
      return unless stale?(etag: cache_version, public: true)

      load_theme_pulse
      load_homepage_context
    end

    private

    def load_theme_pulse
      @body_options = cached_body_options
      pulse = Public::ThemePulse.new(as_of: @as_of, body_name: @body_name.presence)
      @heating_up = pulse.heating_up.select { |stat| stat.surging || (stat.lift && stat.lift > 1) }.first(HEATING_UP_LIMIT)
      @top_themes = pulse.top_themes(limit: TOP_THEMES_LIMIT).select { |stat| stat.current_appearances.positive? }
    end

    def load_homepage_context
      @events = records_in_cached_order(cached_recent_event_ids, Civic::Event.includes(:event_items))
      @stats = cached_stats
      @matter_type_counts = cached_matter_type_counts
    end

    def cache_version
      @cache_version ||= [
        events_index_version,
        Public::CacheVersion.pulse(as_of: @as_of, body_name: @body_name, window: WINDOW)
      ]
    end

    def events_index_version
      @events_index_version ||= Public::CacheVersion.events_index
    end

    def cached_body_options
      Rails.cache.fetch([ events_index_version, "pulse-body-options" ], expires_in: CACHE_TTL) do
        Civic::Event.current_from_source.where.not(body_name: [ nil, "" ]).distinct.order(:body_name).pluck(:body_name)
      end
    end

    def cached_recent_event_ids
      Rails.cache.fetch([ events_index_version, "recent-event-ids" ], expires_in: CACHE_TTL) do
        Civic::Event.recent_first.limit(8).pluck(:id)
      end
    end

    def cached_stats
      Rails.cache.fetch([ events_index_version, "stats" ], expires_in: CACHE_TTL) do
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

    def cached_matter_type_counts
      Rails.cache.fetch([ events_index_version, "matter-type-counts" ], expires_in: CACHE_TTL) do
        Civic::Matter.group(:matter_type_name).order(Arel.sql("COUNT(*) DESC")).limit(6).count
      end
    end

    def records_in_cached_order(ids, scope)
      records_by_id = scope.where(id: ids).index_by(&:id)
      ids.filter_map { |id| records_by_id[id] }
    end
  end
end
