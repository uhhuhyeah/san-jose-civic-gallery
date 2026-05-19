module Public
  class MeetingsController < ApplicationController
    def index
      @month = parsed_month
      @query = params[:q].to_s.strip
      @body_name = params[:body_name].to_s.strip
      return unless stale?(etag: meetings_index_cache_version, public: true)

      @body_options = cached_body_options
      @year_options = cached_year_options

      @events = records_in_cached_order(cached_event_ids, Civic::Event.includes(event_items: { matter: :attachments }))
    end

    private

    INDEX_CACHE_TTL = 5.minutes

    def meetings_index_cache_version
      @meetings_index_cache_version ||= Public::CacheVersion.meetings_index(month: @month, query: @query, body_name: @body_name)
    end

    def public_options_cache_version
      @public_options_cache_version ||= Public::CacheVersion.events_index
    end

    def filtered_events
      scope = Civic::Event.current_from_source
        .where(event_date: @month.beginning_of_month..@month.end_of_month)
      scope = scope.where(body_name: @body_name) if @body_name.present?
      scope = apply_query(scope) if @query.present?
      scope
    end

    def apply_query(scope)
      pattern = "%#{Civic::Event.sanitize_sql_like(@query)}%"
      scope
        .left_joins(event_items: :matter)
        .where(
          "civic_events.title ILIKE :pattern OR " \
          "civic_events.body_name ILIKE :pattern OR " \
          "civic_event_items.title ILIKE :pattern OR " \
          "civic_event_items.matter_file ILIKE :pattern OR " \
          "civic_matters.matter_file ILIKE :pattern OR " \
          "civic_matters.title ILIKE :pattern OR " \
          "civic_matters.name ILIKE :pattern",
          pattern:
        )
        .distinct
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
      years = Civic::Event.current_from_source.where.not(event_date: nil).pluck(Arel.sql("DISTINCT EXTRACT(YEAR FROM event_date)::integer"))
      years << @month.year
      years.compact.uniq.sort.reverse
    end

    def cached_year_options
      Rails.cache.fetch([ public_options_cache_version, "meetings-year-options" ], expires_in: INDEX_CACHE_TTL) do
        year_options
      end
    end

    def cached_body_options
      Rails.cache.fetch([ public_options_cache_version, "meetings-body-options" ], expires_in: INDEX_CACHE_TTL) do
        Civic::Event.current_from_source.where.not(body_name: [ nil, "" ]).distinct.order(:body_name).pluck(:body_name)
      end
    end

    def cached_event_ids
      Rails.cache.fetch([ meetings_index_cache_version, "event-ids" ], expires_in: INDEX_CACHE_TTL) do
        filtered_events.recent_first.limit(100).map(&:id)
      end
    end

    def records_in_cached_order(ids, scope)
      records_by_id = scope.where(id: ids).index_by(&:id)
      ids.filter_map { |id| records_by_id[id] }
    end
  end
end
