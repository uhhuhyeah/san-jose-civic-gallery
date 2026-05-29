require "test_helper"

module Public
  class ThemePulseTest < ActiveSupport::TestCase
    AS_OF = Date.new(2026, 5, 20)

    # Dates relative to AS_OF (window = 13 weeks = 91 days).
    CURRENT_DATE = Date.new(2026, 5, 1)   # within current quarter
    CURRENT_DATE_2 = Date.new(2026, 4, 1) # within current quarter
    PRIOR_DATE = Date.new(2026, 1, 15)    # within prior quarter

    setup do
      @event_seq = 0
      @item_seq = 0
    end

    test "counts current and prior appearances on the primary theme" do
      housing = matter_with_primary("housing", 1)
      appearance(housing, CURRENT_DATE)
      appearance(housing, CURRENT_DATE_2)
      appearance(housing, PRIOR_DATE)

      stat = stat_for("housing", min_appearances: 1)

      assert_equal 2, stat.current_appearances
      assert_equal 1, stat.prior_appearances
    end

    test "heating_up excludes themes below the minimum-appearances floor" do
      housing = matter_with_primary("housing", 1)
      2.times { appearance(housing, CURRENT_DATE) } # only 2 appearances

      heating = ThemePulse.new(jurisdiction: civic_jurisdictions(:sanjose), as_of: AS_OF, min_appearances: 3).heating_up.map(&:slug)

      assert_not_includes heating, "housing"
    end

    test "heating_up flags a surging theme with no prior baseline first" do
      surging = matter_with_primary("homelessness", 1)
      steady = matter_with_primary("budget_finance", 2)
      3.times { appearance(surging, CURRENT_DATE) } # 3 now, 0 prior -> surging
      3.times { appearance(steady, CURRENT_DATE) }
      3.times { appearance(steady, PRIOR_DATE) }    # flat

      heating = ThemePulse.new(jurisdiction: civic_jurisdictions(:sanjose), as_of: AS_OF, min_appearances: 3).heating_up

      assert_equal "homelessness", heating.first.slug
      assert heating.first.surging
    end

    test "body_name restricts appearances to that body" do
      housing = matter_with_primary("housing", 1)
      appearance(housing, CURRENT_DATE, body_name: "City Council")
      appearance(housing, CURRENT_DATE, body_name: "Planning Commission")

      council = ThemePulse.new(jurisdiction: civic_jurisdictions(:sanjose), as_of: AS_OF, body_name: "City Council", min_appearances: 1)

      assert_equal 1, council.stats.find { |s| s.slug == "housing" }.current_appearances
    end

    test "ignores non-current-source events and event items" do
      housing = matter_with_primary("housing", 1)
      appearance(housing, CURRENT_DATE)
      appearance(housing, CURRENT_DATE, event_present: false)
      appearance(housing, CURRENT_DATE, item_present: false)

      assert_equal 1, stat_for("housing", min_appearances: 1).current_appearances
    end

    test "only the primary theme accrues appearances" do
      matter = Civic::Matter.create!(legistar_matter_id: 700, matter_file: "26-700")
      matter.themes.create!(theme_slug: "housing", rank: 1)
      matter.themes.create!(theme_slug: "land_use_zoning", rank: 2)
      appearance(matter, CURRENT_DATE)

      pulse = ThemePulse.new(jurisdiction: civic_jurisdictions(:sanjose), as_of: AS_OF, min_appearances: 1)

      assert_equal 1, pulse.stats.find { |s| s.slug == "housing" }.current_appearances
      assert_equal 0, pulse.stats.find { |s| s.slug == "land_use_zoning" }.current_appearances
    end

    test "quarterly_series returns a four-bucket array per theme in the taxonomy" do
      housing = matter_with_primary("housing", 1)
      transportation = matter_with_primary("transportation", 2)
      # Spread housing appearances across all 4 quarters so we can verify each
      # bucket. AS_OF = 2026-05-20; window = 13 weeks. Bucket boundaries:
      #   bucket 0 (oldest):  ~2025-05-21 .. ~2025-08-19
      #   bucket 1:           ~2025-08-19 .. ~2025-11-19
      #   bucket 2:           ~2025-11-19 .. ~2026-02-18
      #   bucket 3 (current): ~2026-02-18 ..  2026-05-20  (closed)
      appearance(housing, Date.new(2025, 7, 1))   # bucket 0
      appearance(housing, Date.new(2025, 7, 15))  # bucket 0
      appearance(housing, Date.new(2025, 10, 1))  # bucket 1
      appearance(housing, Date.new(2026, 1, 15))  # bucket 2
      appearance(housing, CURRENT_DATE)           # bucket 3
      appearance(housing, CURRENT_DATE_2)         # bucket 3
      appearance(transportation, CURRENT_DATE)    # only in bucket 3

      pulse = ThemePulse.new(jurisdiction: civic_jurisdictions(:sanjose), as_of: AS_OF)
      series = pulse.quarterly_series

      assert_equal [ 2, 1, 1, 2 ], series.fetch("housing")
      assert_equal [ 0, 0, 0, 1 ], series.fetch("transportation")
    end

    test "quarterly_series includes every theme in the taxonomy, even with zero appearances" do
      pulse = ThemePulse.new(jurisdiction: civic_jurisdictions(:sanjose), as_of: AS_OF)
      series = pulse.quarterly_series

      taxonomy_slugs = Civic::ThemeTaxonomy.themes_for(civic_jurisdictions(:sanjose)).map { |t| t[:slug] }
      assert_equal taxonomy_slugs.sort, series.keys.sort
      series.each_value { |bucket| assert_equal [ 0, 0, 0, 0 ], bucket }
    end

    test "quarterly_series honors a custom bucket count" do
      housing = matter_with_primary("housing", 3)
      appearance(housing, CURRENT_DATE)

      series = ThemePulse.new(jurisdiction: civic_jurisdictions(:sanjose), as_of: AS_OF).quarterly_series(buckets: 8)

      assert_equal 8, series.fetch("housing").length
      assert_equal 1, series.fetch("housing").last
    end

    test "quarterly_series last bucket aligns with stats.current_appearances" do
      housing = matter_with_primary("housing", 4)
      appearance(housing, CURRENT_DATE)
      appearance(housing, CURRENT_DATE_2)
      appearance(housing, AS_OF) # exactly the as_of boundary; closed end keeps it in current

      pulse = ThemePulse.new(jurisdiction: civic_jurisdictions(:sanjose), as_of: AS_OF, min_appearances: 1)
      housing_stat = pulse.stats.find { |s| s.slug == "housing" }

      assert_equal housing_stat.current_appearances, pulse.quarterly_series.fetch("housing").last
    end

    test "uses the jurisdiction's own theme vocabulary" do
      matter = Civic::Matter.create!(
        source_system: "simbli.sjusd",
        source_matter_id: "sjusd:57394:item-1",
        matter_file: "SJUSD-57394-1"
      )
      matter.themes.create!(theme_slug: "special_education", rank: 1)
      event = Civic::Event.create!(
        source_system: "simbli.sjusd",
        source_event_id: "sjusd:evt-1",
        event_date: CURRENT_DATE,
        body_name: "Board of Education"
      )
      Civic::EventItem.create!(
        source_system: "simbli.sjusd",
        source_event_item_id: "sjusd:evt-1:item-1",
        civic_event_id: event.id,
        civic_matter_id: matter.id
      )

      pulse = ThemePulse.new(jurisdiction: civic_jurisdictions(:sjusd), as_of: AS_OF, min_appearances: 1)
      slugs = pulse.stats.map(&:slug)

      assert_includes slugs, "special_education"
      assert_not_includes slugs, "housing"
      assert_equal 1, pulse.stats.find { |stat| stat.slug == "special_education" }.current_appearances
    end

    private

    def matter_with_primary(slug, legistar)
      matter = Civic::Matter.create!(legistar_matter_id: legistar, matter_file: "26-#{legistar}")
      matter.themes.create!(theme_slug: slug, rank: 1)
      matter
    end

    def appearance(matter, event_date, body_name: "City Council", event_present: true, item_present: true)
      @event_seq += 1
      @item_seq += 1
      event = Civic::Event.create!(
        legistar_event_id: 10_000 + @event_seq,
        event_date:,
        body_name:,
        source_present: event_present
      )
      Civic::EventItem.create!(
        legistar_event_item_id: 20_000 + @item_seq,
        civic_event_id: event.id,
        civic_matter_id: matter.id,
        source_present: item_present
      )
      event
    end

    def stat_for(slug, min_appearances:)
      ThemePulse.new(jurisdiction: civic_jurisdictions(:sanjose), as_of: AS_OF, min_appearances:).stats.find { |stat| stat.slug == slug }
    end
  end
end
