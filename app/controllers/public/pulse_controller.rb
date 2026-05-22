module Public
  # The homepage (root). Composes the theme Pulse with the homepage furniture
  # (recent meetings, source-record and record-type counts). The former events
  # index still lives at /public/events; its data loading could be consolidated
  # here later. See docs/pulse.md.
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
      stats = cached_theme_stats
      @heating_up = stats.select(&:eligible).sort_by { |stat| [ stat.surging ? 0 : 1, -(stat.lift || 0) ] }
        .select { |stat| stat.surging || (stat.lift && stat.lift > 1) }
        .first(HEATING_UP_LIMIT)
      @top_themes = stats.sort_by { |stat| -stat.current_appearances }.first(TOP_THEMES_LIMIT).select { |stat| stat.current_appearances.positive? }
    end

    def load_homepage_context
      @events = records_in_cached_order(cached_recent_event_ids, Civic::Event.for_jurisdiction(current_jurisdiction).includes(:event_items))
      @stats = cached_stats
      @matter_type_counts = cached_matter_type_counts
    end

    def cache_version
      @cache_version ||= [
        "public/pulse-homepage/v2",
        current_jurisdiction.slug,
        @as_of.iso8601,
        Public::CacheVersion.query_digest(@body_name),
        WINDOW.to_i,
        Time.current.to_i / CACHE_TTL.to_i
      ].join("/")
    end

    def cached_theme_stats
      Rails.cache.fetch([ cache_version, "theme-stats" ], expires_in: CACHE_TTL) do
        Public::ThemePulse.new(jurisdiction: current_jurisdiction, as_of: @as_of, body_name: @body_name.presence).stats
      end
    end

    def cached_body_options
      Rails.cache.fetch([ cache_version, "pulse-body-options" ], expires_in: CACHE_TTL) do
        Civic::Event.current_from_source.for_jurisdiction(current_jurisdiction).where.not(body_name: [ nil, "" ]).distinct.order(:body_name).pluck(:body_name)
      end
    end

    def cached_recent_event_ids
      Rails.cache.fetch([ cache_version, "recent-event-ids" ], expires_in: CACHE_TTL) do
        Civic::Event.for_jurisdiction(current_jurisdiction).recent_first.limit(8).pluck(:id)
      end
    end

    def cached_stats
      Rails.cache.fetch([ cache_version, "stats" ], expires_in: CACHE_TTL) do
        {
          meetings: Civic::Event.current_from_source.for_jurisdiction(current_jurisdiction).count,
          agenda_items: Civic::EventItem.current_from_source.for_jurisdiction(current_jurisdiction).count,
          matters: Civic::Matter.for_jurisdiction(current_jurisdiction).count,
          attachments: Civic::MatterAttachment.current_from_source.for_jurisdiction(current_jurisdiction).count,
          imported_files: Civic::MatterAttachment.imported.for_jurisdiction(current_jurisdiction).count,
          extracted_texts: Documents::ExtractedText.where(status: "ok").joins(:matter_attachment).merge(Civic::MatterAttachment.for_jurisdiction(current_jurisdiction)).count
        }
      end
    end

    def cached_matter_type_counts
      Rails.cache.fetch([ cache_version, "matter-type-counts" ], expires_in: CACHE_TTL) do
        Civic::Matter.for_jurisdiction(current_jurisdiction).group(:matter_type_name).order(Arel.sql("COUNT(*) DESC")).limit(6).count
      end
    end

    def records_in_cached_order(ids, scope)
      records_by_id = scope.where(id: ids).index_by(&:id)
      ids.filter_map { |id| records_by_id[id] }
    end
  end
end
