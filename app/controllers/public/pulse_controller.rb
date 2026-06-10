module Public
  # The homepage (root). Composes the theme Pulse with the homepage furniture.
  # See docs/pulse.md and docs/redesign-plan.md.
  class PulseController < ApplicationController
    WINDOW = Public::ThemePulse::DEFAULT_WINDOW
    SPARK_BUCKETS = Public::ThemePulse::DEFAULT_SPARK_BUCKETS
    HEATING_UP_LIMIT = 6
    HEATING_UP_RAIL_LIMIT = 4
    RECENT_DECISIONS_LIMIT = 3
    CALENDAR_LIMIT = 8
    CACHE_TTL = 10.minutes

    def show
      @body_name = params[:body_name].to_s.strip
      @as_of = Date.current
      return unless stale?(etag: cache_version, public: true)

      load_theme_pulse
      load_homepage_context
      load_atlas
    end

    private

    def load_theme_pulse
      payload = cached_homepage_payload
      @body_options = payload[:body_options]
      @theme_stats = payload[:theme_stats]
      @quarterly_series = payload[:quarterly_series]
      @heating_up = @theme_stats.select(&:eligible).sort_by { |stat| [ stat.surging ? 0 : 1, -(stat.lift || 0) ] }
        .select { |stat| stat.surging || (stat.lift && stat.lift > 1) }
        .first(HEATING_UP_LIMIT)
    end

    def load_homepage_context
      payload = cached_homepage_payload
      @events = records_in_cached_order(payload[:recent_event_ids], Civic::Event.for_jurisdiction(current_jurisdiction))
      @stats = payload[:stats]
      @recent_decisions = records_in_cached_order(
        payload[:recent_decision_ids],
        Civic::Matter.for_jurisdiction(current_jurisdiction).includes(:themes, attachments: :generated_artifacts)
      )
    end

    # Atlas data: every theme in the taxonomy, sorted by current-quarter
    # appearances, with a size bucket and a quarterly sparkline series attached.
    # The dense grid layout in the view lets the biggest tile anchor the
    # composition while long-tail tiles fill in around it.
    def load_atlas
      @atlas_tiles = @theme_stats
        .sort_by { |stat| [ -stat.current_appearances, stat.label ] }
        .each_with_index
        .map do |stat, rank|
          {
            stat: stat,
            rank: rank,
            size: atlas_size_for(rank),
            series: @quarterly_series.fetch(stat.slug, Array.new(SPARK_BUCKETS, 0))
          }
        end
    end

    # Tile-size buckets driven by rank in the appearance-descending sort. With
    # 17 themes in the SANJOSE taxonomy this yields 1 XL · 2 L · 8 M · 6 S, the
    # composition the mockup uses. Override in a subclass / tweak here if the
    # ratio needs to change.
    def atlas_size_for(rank)
      case rank
      when 0 then :xl
      when 1, 2 then :l
      when 3..10 then :m
      else :s
      end
    end

    # The data version replaces the wall-clock TTL bucket that used to sit
    # here: the ETag (and the payload behind it) now changes when ingestion
    # writes new data or the day rolls over, instead of every ten minutes.
    def cache_version
      @cache_version ||= [
        "public/pulse-homepage/v4",
        current_jurisdiction.slug,
        @as_of.iso8601,
        Public::CacheVersion.query_digest(@body_name),
        WINDOW.to_i,
        SPARK_BUCKETS,
        current_jurisdiction.data_version
      ].join("/")
    end

    # Everything the homepage needs from the database, in one cache entry: a
    # warm render costs a single cache read. This page previously kept five
    # entries (pulse payload, body options, recent events, recent decisions,
    # stats); with a database-backed cache store each read was a network
    # round-trip, so consolidating them mattered as much as caching them.
    def cached_homepage_payload
      @cached_homepage_payload ||= Rails.cache.fetch([ cache_version, "homepage-payload" ], expires_in: CACHE_TTL) do
        pulse = Public::ThemePulse.new(jurisdiction: current_jurisdiction, as_of: @as_of, body_name: @body_name.presence)
        {
          theme_stats: pulse.stats,
          quarterly_series: pulse.quarterly_series(buckets: SPARK_BUCKETS),
          body_options: body_options,
          recent_event_ids: recent_event_ids,
          recent_decision_ids: recent_decision_ids,
          stats: stats
        }
      end
    end

    def body_options
      Civic::Event.current_from_source.for_jurisdiction(current_jurisdiction).where.not(body_name: [ nil, "" ]).distinct.order(:body_name).pluck(:body_name)
    end

    def recent_event_ids
      Civic::Event.for_jurisdiction(current_jurisdiction).recent_first.limit(CALENDAR_LIMIT).pluck(:id)
    end

    # Recent matters that already have a non-empty generated summary on a current
    # attachment, newest agendas first. The summary text itself is read in the
    # view from the preloaded artifacts (see matter_summary_preview).
    def recent_decision_ids
      summarized_attachment_ids = Generated::Artifact
        .succeeded
        .for_kind(Generated::SummarizeMatterAttachment::KIND)
        .where(prompt_version: Generated::SummarizeMatterAttachment::PROMPT::VERSION)
        .where(target_type: "Civic::MatterAttachment")
        .where("content->>'summary' <> ''")
        .select(:target_id)

      matter_ids = Civic::MatterAttachment
        .current_from_source
        .for_jurisdiction(current_jurisdiction)
        .where(id: summarized_attachment_ids)
        .select(:civic_matter_id)

      Civic::Matter
        .for_jurisdiction(current_jurisdiction)
        .where(id: matter_ids)
        .recent_first
        .limit(RECENT_DECISIONS_LIMIT)
        .pluck(:id)
    end

    def stats
      {
        meetings: Civic::Event.current_from_source.for_jurisdiction(current_jurisdiction).count,
        agenda_items: Civic::EventItem.current_from_source.for_jurisdiction(current_jurisdiction).count,
        matters_heard: Civic::EventItem.current_from_source.for_jurisdiction(current_jurisdiction).where.not(civic_matter_id: nil).count,
        matters: Civic::Matter.for_jurisdiction(current_jurisdiction).count,
        attachments: Civic::MatterAttachment.current_from_source.for_jurisdiction(current_jurisdiction).count,
        imported_files: Civic::MatterAttachment.imported.for_jurisdiction(current_jurisdiction).count,
        extracted_texts: Documents::ExtractedText.where(status: "ok").joins(:matter_attachment).merge(Civic::MatterAttachment.for_jurisdiction(current_jurisdiction)).count
      }
    end

    def records_in_cached_order(ids, scope)
      records_by_id = scope.where(id: ids).index_by(&:id)
      ids.filter_map { |id| records_by_id[id] }
    end
  end
end
