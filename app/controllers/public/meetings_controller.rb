module Public
  class MeetingsController < ApplicationController
    def index
      @month = parsed_month
      @query = params[:q].to_s.strip
      @body_name = params[:body_name].to_s.strip
      @body_options = Civic::Event.current_from_source.where.not(body_name: [ nil, "" ]).distinct.order(:body_name).pluck(:body_name)
      @year_options = year_options

      @events = filtered_events
        .includes(event_items: { matter: :attachments })
        .recent_first
        .limit(100)
    end

    private

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
  end
end
