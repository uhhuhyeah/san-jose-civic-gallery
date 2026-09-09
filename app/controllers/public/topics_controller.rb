module Public
  # Durable topical landing pages (issue #152). /topics is the hub of theme
  # records; /topics/:slug is the crawlable entry point for one theme, linking
  # into matters, meetings, and the filtered matters listing. Everything is
  # scoped to the request's jurisdiction: the theme vocabularies themselves
  # differ per jurisdiction, so a slug valid in one host 404s on another.
  class TopicsController < ApplicationController
    MATTERS_LIMIT = 50
    MEETINGS_LIMIT = 10
    INDEX_CACHE_TTL = 5.minutes

    def index
      return unless stale?(etag: index_cache_version, public: true)

      @themes = cached_populated_themes
    end

    def show
      @theme = Civic::ThemeTaxonomy.slug_from_url(params[:slug])
      unless Civic::ThemeTaxonomy.valid_slug?(@theme, current_jurisdiction)
        head :not_found
        return
      end

      @theme_label = Civic::ThemeTaxonomy.label_for(@theme, current_jurisdiction)
      return unless stale?(etag: show_cache_version, public: true)

      @matters = records_in_cached_order(cached_matter_ids, matter_scope)
      @meetings = records_in_cached_order(cached_event_ids, event_scope)
      @empty = @matters.empty? && @meetings.empty?
    end

    private

    def index_cache_version
      @index_cache_version ||= Public::CacheVersion.topics_index(jurisdiction: current_jurisdiction)
    end

    def show_cache_version
      @show_cache_version ||= Public::CacheVersion.topic_landing(slug: @theme, jurisdiction: current_jurisdiction)
    end

    # Only themes with at least one tagged matter, so the hub never links to
    # a thin (noindex) landing page.
    def cached_populated_themes
      Rails.cache.fetch([ index_cache_version, "populated-themes" ], expires_in: INDEX_CACHE_TTL) do
        counts = Civic::Matter
          .for_jurisdiction(current_jurisdiction)
          .joins(:themes)
          .group("civic_matter_themes.theme_slug")
          .count

        Civic::ThemeTaxonomy
          .themes_for(current_jurisdiction)
          .filter_map do |theme|
            count = counts[theme[:slug]].to_i
            next if count.zero?

            {
              slug: theme[:slug],
              url_slug: Civic::ThemeTaxonomy.url_slug_for(theme[:slug]),
              label: theme[:label],
              matter_count: count
            }
          end
      end
    end

    def matter_scope
      Civic::Matter.for_jurisdiction(current_jurisdiction).includes(:attachments, :themes)
    end

    def event_scope
      Civic::Event.for_jurisdiction(current_jurisdiction).includes(event_items: { matter: :attachments })
    end

    # Any-rank match, primary-theme (rank 1) matters first, mirroring the
    # theme branch of MattersController#matter_ids_for.
    def cached_matter_ids
      Rails.cache.fetch([ show_cache_version, "matter-ids" ], expires_in: INDEX_CACHE_TTL) do
        Civic::Matter
          .for_jurisdiction(current_jurisdiction)
          .joins(:themes)
          .where(civic_matter_themes: { theme_slug: @theme })
          .order(Arel.sql("civic_matter_themes.rank ASC"))
          .recent_first
          .limit(MATTERS_LIMIT)
          .pluck(:id)
      end
    end

    # Meetings whose current agendas include a matter tagged with this theme.
    # Resolved as an id subquery rather than a joins through the event_items
    # association, because that association's agenda_order scope would pollute
    # the outer ORDER BY, and DISTINCT + ORDER BY would violate Postgres's
    # select-list rule under pluck.
    def cached_event_ids
      Rails.cache.fetch([ show_cache_version, "event-ids" ], expires_in: INDEX_CACHE_TTL) do
        themed_event_ids = Civic::EventItem
          .current_from_source
          .joins(matter: :themes)
          .where(civic_matter_themes: { theme_slug: @theme })
          .select(:civic_event_id)

        Civic::Event
          .current_from_source
          .for_jurisdiction(current_jurisdiction)
          .where(id: themed_event_ids)
          .recent_first
          .limit(MEETINGS_LIMIT)
          .pluck(:id)
      end
    end

    def records_in_cached_order(ids, scope)
      records_by_id = scope.where(id: ids).index_by(&:id)
      ids.filter_map { |id| records_by_id[id] }
    end
  end
end
