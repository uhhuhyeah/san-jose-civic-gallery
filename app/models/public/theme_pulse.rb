module Public
  # Computes the "pulse" of civic themes: how often each theme's matters appear
  # on agendas, comparing the current quarter to the prior one. Appearances are
  # counted on a matter's PRIMARY (rank 1) theme only, so secondary-tag noise
  # does not inflate the signal.
  #
  # The `heating_up` view ranks themes by momentum (current rate vs prior-quarter
  # rate), gated by a minimum-appearances floor so a single agenda item can't
  # spike a theme. `stats` exposes the full per-theme breakdown.
  #
  # Rates are appearances per meeting in the window, which keeps the comparison
  # fair when the two windows hold different numbers of meetings (recess, etc.)
  # and when comparing a single body.
  class ThemePulse
    DEFAULT_WINDOW = 13.weeks
    DEFAULT_MIN_APPEARANCES = 3

    ThemeStat = Data.define(
      :slug, :label,
      :current_appearances, :prior_appearances,
      :current_rate, :prior_rate, :lift, :surging, :eligible
    )

    def initialize(jurisdiction:, as_of: Date.current, body_name: nil, window: DEFAULT_WINDOW, min_appearances: DEFAULT_MIN_APPEARANCES)
      @jurisdiction = jurisdiction
      @as_of = as_of
      @body_name = body_name.presence
      @window = window
      @min_appearances = min_appearances
    end

    # Surging themes (real activity now, none last quarter) first, then by lift.
    def heating_up(limit: nil)
      sorted = stats.select(&:eligible).sort_by do |stat|
        [ stat.surging ? 0 : 1, -(stat.lift || 0) ]
      end
      limit ? sorted.first(limit) : sorted
    end

    def stats
      @stats ||= build_stats
    end

    private

    attr_reader :jurisdiction, :as_of, :body_name, :window, :min_appearances

    def build_stats
      current = appearances_by_theme(current_range)
      prior = appearances_by_theme(prior_range)
      current_meetings = meetings_in(current_range)
      prior_meetings = meetings_in(prior_range)

      Civic::ThemeTaxonomy.themes_for(jurisdiction).map do |theme|
        slug = theme[:slug]
        current_appearances = current[slug] || 0
        prior_appearances = prior[slug] || 0
        current_rate = rate(current_appearances, current_meetings)
        prior_rate = rate(prior_appearances, prior_meetings)
        surging = prior_rate.zero? && current_appearances.positive?

        ThemeStat.new(
          slug:,
          label: theme[:label],
          current_appearances:,
          prior_appearances:,
          current_rate:,
          prior_rate:,
          lift: prior_rate.zero? ? nil : (current_rate / prior_rate),
          surging:,
          eligible: current_appearances >= min_appearances
        )
      end
    end

    def appearances_by_theme(range)
      scope = Civic::MatterTheme.primary
        .joins(matter: { event_items: :event })
        .where(civic_event_items: { source_present: true })
        .where(civic_events: { source_present: true, event_date: range, civic_jurisdiction_id: jurisdiction.id })
      scope = scope.where(civic_events: { body_name: }) if body_name
      scope.group("civic_matter_themes.theme_slug").count
    end

    def meetings_in(range)
      scope = Civic::Event.current_from_source.for_jurisdiction(jurisdiction).where(event_date: range)
      scope = scope.where(body_name:) if body_name
      scope.count
    end

    def rate(appearances, meetings)
      meetings.zero? ? 0.0 : appearances.to_f / meetings
    end

    def current_range
      (as_of - window)..as_of
    end

    def prior_range
      (as_of - (window * 2))...(as_of - window)
    end
  end
end
