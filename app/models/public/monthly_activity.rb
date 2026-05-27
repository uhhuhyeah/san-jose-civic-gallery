module Public
  # Assembles the deterministic facts for a single month of civic activity:
  # matters that were passed and matters that were introduced.  Does not call
  # any AI/LLM — only reads from the database.
  class MonthlyActivity
    Decision = Data.define(:matter, :passed_date, :primary_theme_label)
    Introduction = Data.define(:matter, :intro_date, :primary_theme_label)

    def initialize(jurisdiction:, period_start:, period_end:)
      @jurisdiction = jurisdiction
      @period_start = period_start
      @period_end = period_end
    end

    # Matters passed during the period, newest first.
    def decisions
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

    # Matters introduced during the period, newest first.
    def introduced
      matters = Civic::Matter
                .for_jurisdiction(@jurisdiction)
                .includes(:themes)
                .where(intro_date: @period_start..@period_end)
                .where.not(intro_date: nil)
                .order(intro_date: :desc, id: :desc)
                .to_a

      matters.map do |matter|
        Introduction.new(
          matter: matter,
          intro_date: matter.intro_date,
          primary_theme_label: primary_theme_label(matter.themes),
        )
      end
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
