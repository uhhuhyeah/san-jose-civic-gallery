module Generated
  # Batch orchestrator for monthly roundups. For each jurisdiction it finds the
  # most recent CLOSED activity-months (months with civic events or matters that
  # are fully in the past) and delegates each to SummarizeRoundup. A period that
  # already holds a succeeded monthly_roundup artifact is frozen and skipped
  # unless force: true is passed.
  class BackfillMonthlyRoundups
    DEFAULT_LIMIT = 1
    MAX_SCAN_MONTHS = 24

    Result = Data.define(:dry_run, :candidates, :generated, :failed, :skipped)

    def self.call(limit: DEFAULT_LIMIT, dry_run: true, client: RoundupClient.new, force: false,
                  jurisdiction: nil, month: nil, as_of: Date.current)
      new(limit:, dry_run:, client:, force:, jurisdiction:, month:, as_of:).call
    end

    # month: nil for auto-detect, or a Date (any day in the target month) to
    # target one specific month.
    def initialize(limit:, dry_run:, client:, force:, jurisdiction:, month:, as_of:)
      @limit = limit.to_i
      @dry_run = dry_run
      @client = client
      @force = force
      @jurisdiction = jurisdiction
      @month = month
      @as_of = as_of
    end

    def call
      candidates = candidate_periods
      generated = 0
      failed = 0
      skipped = 0

      unless dry_run
        candidates.each do |period|
          result = SummarizeRoundup.call(period:, client:, force:)
          if result.artifact.status == "succeeded"
            result.skipped ? skipped += 1 : generated += 1
          else
            failed += 1
          end
        end
      end

      Result.new(dry_run:, candidates:, generated:, failed:, skipped:)
    end

    private

    attr_reader :limit, :dry_run, :client, :force, :jurisdiction, :month, :as_of

    # All jurisdictions when none is given; otherwise just the one.
    def jurisdictions
      jurisdiction ? [jurisdiction] : Civic::Jurisdiction.all.to_a
    end

    def candidate_periods
      jurisdictions.flat_map { |j| candidate_periods_for(j) }
    end

    def candidate_periods_for(j)
      months = month ? [explicit_month] : recent_activity_months(j)
      periods = months.filter_map do |first_of_month|
        next unless closed?(first_of_month)
        Civic::RoundupPeriod.for_month(
          jurisdiction: j,
          year: first_of_month.year,
          month: first_of_month.month
        )
      end
      force ? periods : periods.reject { |p| frozen?(p) }
    end

    # The explicit MONTH override targets exactly one month (activity gate is
    # bypassed).
    def explicit_month
      month.beginning_of_month
    end

    # Up to `limit` most-recent CLOSED months (walking back from the previous
    # calendar month) that have civic activity for this jurisdiction. Bounded by
    # MAX_SCAN_MONTHS.
    def recent_activity_months(j)
      found = []
      cursor = (as_of.beginning_of_month - 1.month)
      scanned = 0
      while found.size < limit && scanned < MAX_SCAN_MONTHS
        found << cursor if month_has_activity?(j, cursor.beginning_of_month, cursor.end_of_month)
        cursor -= 1.month
        scanned += 1
      end
      found
    end

    def closed?(first_of_month)
      first_of_month.end_of_month < as_of
    end

    def month_has_activity?(j, period_start, period_end)
      Civic::Event.for_jurisdiction(j).where(event_date: period_start..period_end).exists? ||
        Civic::Matter.for_jurisdiction(j).where(passed_date: period_start..period_end).exists? ||
        Civic::Matter.for_jurisdiction(j).where(intro_date: period_start..period_end).exists?
    end

    # FREEZE: a period with any succeeded monthly_roundup artifact is frozen.
    def frozen?(period)
      Generated::Artifact.exists?(
        target: period,
        kind: SummarizeRoundup::KIND,
        status: "succeeded"
      )
    end
  end
end
