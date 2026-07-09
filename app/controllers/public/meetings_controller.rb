module Public
  class MeetingsController < ApplicationController
    include PublicRateLimitedSearch

    def index
      @month = parsed_month
      @query = params[:q].to_s.strip
      @body_name = params[:body_name].to_s.strip
      return unless stale?(etag: meetings_index_cache_version, public: true)

      options = cached_filter_options
      @body_options = options[:body_options]
      @year_options = options[:year_options]

      @events = records_in_cached_order(cached_event_ids, Civic::Event.for_jurisdiction(current_jurisdiction).includes(event_items: { matter: :attachments }))
    end

    private

    INDEX_CACHE_TTL = 5.minutes

    def meetings_index_cache_version
      @meetings_index_cache_version ||= Public::CacheVersion.meetings_index(month: @month, query: @query, body_name: @body_name, jurisdiction: current_jurisdiction)
    end

    def public_options_cache_version
      @public_options_cache_version ||= Public::CacheVersion.events_index(jurisdiction: current_jurisdiction)
    end

    def filtered_events
      scope = Civic::Event.current_from_source.for_jurisdiction(current_jurisdiction)
        .where(event_date: @month.beginning_of_month..@month.end_of_month)
      scope = scope.where(body_name: @body_name) if @body_name.present?
      scope = apply_query(scope) if @query.present?
      scope
    end

    def apply_query(scope)
      scope.where(
        "to_tsvector('english', coalesce(civic_events.searchable_text, '')) @@ plainto_tsquery('english', ?)",
        @query
      )
    end

    def parsed_month
      if params[:year].present? || params[:month_number].present?
        year = params[:year].to_i
        month_number = params[:month_number].to_i
        return Date.new(year, month_number, 1) if year.positive? && month_number.between?(1, 12)
      end

      raw_month = params[:month].to_s
      return Date.current.beginning_of_month if raw_month.blank?

      Date.strptime(raw_month, "%Y-%m").beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end

    def year_options
      years = Civic::Event.current_from_source.for_jurisdiction(current_jurisdiction).where.not(event_date: nil).pluck(Arel.sql("DISTINCT EXTRACT(YEAR FROM event_date)::integer"))
      years << @month.year
      years.compact.uniq.sort.reverse
    end

    # Body and year filter options cached as one entry: they invalidate
    # together (any event change) and a warm render does one cache read
    # instead of two.
    def cached_filter_options
      Rails.cache.fetch([ public_options_cache_version, "meetings-filter-options" ], expires_in: INDEX_CACHE_TTL) do
        {
          body_options: Civic::Event.current_from_source.for_jurisdiction(current_jurisdiction).where.not(body_name: [ nil, "" ]).distinct.order(:body_name).pluck(:body_name),
          year_options: year_options
        }
      end
    end

    def cached_event_ids
      Rails.cache.fetch([ meetings_index_cache_version, "event-ids" ], expires_in: INDEX_CACHE_TTL) do
        scope = filtered_events
        scope = if @query.present?
          rank_sql = Arel.sql("ts_rank(to_tsvector('english', coalesce(civic_events.searchable_text, '')), plainto_tsquery('english', #{Civic::Event.connection.quote(@query)})) DESC")
          scope.reorder(rank_sql, "civic_events.event_date DESC", "civic_events.legistar_event_id DESC")
        else
          scope.recent_first
        end
        scope.limit(100).map(&:id)
      end
    end

    def records_in_cached_order(ids, scope)
      records_by_id = scope.where(id: ids).index_by(&:id)
      ids.filter_map { |id| records_by_id[id] }
    end
  end
end
