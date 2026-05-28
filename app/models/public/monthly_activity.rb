module Public
  # Assembles the deterministic facts for a single month of civic activity:
  # matters that were passed, matters that were introduced, meetings with
  # summaries, theme momentum, and a quiet-month flag.  Does not call any
  # AI/LLM — only reads from the database.
  class MonthlyActivity
    Decision = Data.define(:matter, :passed_date, :primary_theme_label)
    Introduction = Data.define(:matter, :intro_date, :primary_theme_label)
    Meeting = Data.define(:event, :summary, :key_topics)

    THEME_MOMENTUM_LIMIT = 5
    QUIET_MONTH_THRESHOLD = 3
    # Cap on introductions surfaced in the roundup. Keeps the digest focused and
    # the prompt input bounded even in a heavy month (April had 60 themed intros).
    INTRODUCED_LIMIT = 40

    def initialize(jurisdiction:, period_start:, period_end:)
      @jurisdiction = jurisdiction
      @period_start = period_start
      @period_end = period_end
    end

    # Matters passed during the period, newest first.
    def decisions
      @decisions ||= begin
        matters = Civic::Matter
                  .for_jurisdiction(@jurisdiction)
                  .includes(:themes)
                  .where(passed_date: @period_start..@period_end)
                  .where.not(passed_date: nil)
                  .order(passed_date: :desc, id: :desc)
                  .to_a

        matters.map do |matter|
          Decision.new(
            matter: matter,
            passed_date: matter.passed_date,
            primary_theme_label: primary_theme_label(matter.themes),
          )
        end
      end
    end

    # Substantive matters introduced during the period, newest first, capped.
    # Restricted to matters that received a primary (rank-1) theme: ClassifyMatterThemes
    # deliberately leaves procedural and ceremonial matters untagged, so a primary
    # theme is the substantive-vs-procedural signal. This keeps the roundup an
    # editorial digest rather than a raw dump of every agenda item.
    def introduced
      @introduced ||= begin
        matters = Civic::Matter
                  .for_jurisdiction(@jurisdiction)
                  .includes(:themes)
                  .where(intro_date: @period_start..@period_end)
                  .where.not(intro_date: nil)
                  .where(id: Civic::MatterTheme.primary.select(:civic_matter_id))
                  .order(intro_date: :desc, id: :desc)
                  .limit(INTRODUCED_LIMIT)
                  .to_a

        matters.map do |matter|
          Introduction.new(
            matter: matter,
            intro_date: matter.intro_date,
            primary_theme_label: primary_theme_label(matter.themes),
          )
        end
      end
    end

    # Meetings with a succeeded event-summary artifact, newest first.
    def meetings
      @meetings ||= begin
        events = Civic::Event
          .for_jurisdiction(@jurisdiction)
          .current_from_source
          .where(event_date: @period_start..@period_end)
          .recent_first
          .to_a

        return [] if events.empty?

        artifacts = Generated::Artifact.succeeded
          .for_kind(Generated::SummarizeEvent::KIND)
          .where(prompt_version: Generated::SummarizeEvent::PROMPT::VERSION)
          .where(target_type: "Civic::Event", target_id: events.map(&:id))
          .recent_first
          .to_a

        # Group by target_id; first in recent_first order = newest artifact.
        artifacts_by_event = artifacts.group_by(&:target_id)

        events.filter_map do |event|
          artifact = artifacts_by_event[event.id]&.first
          next unless artifact

          Meeting.new(
            event: event,
            summary: artifact.content["summary"].to_s,
            key_topics: Array(artifact.content["key_topics"]),
          )
        end
      end
    end

    # Top surging themes for the month.
    def theme_momentum
      @theme_momentum ||= begin
        pulse = Public::ThemePulse.new(
          jurisdiction: @jurisdiction,
          as_of: @period_end,
          window: (@period_end - @period_start).to_i.days,
        )
        pulse.heating_up(limit: THEME_MOMENTUM_LIMIT)
      end
    end

    # True when both decisions and introductions are below threshold.
    def quiet_month?
      decisions.size < QUIET_MONTH_THRESHOLD && introduced.size < QUIET_MONTH_THRESHOLD
    end

    private

    # Return the label of the rank-1 theme, or nil if none.
    # `themes` is expected to be already loaded (via .includes).
    def primary_theme_label(themes)
      primary = themes.detect { |t| t.rank == 1 }
      primary&.label
    end
  end
end
