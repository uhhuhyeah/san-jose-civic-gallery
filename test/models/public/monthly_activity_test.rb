require "test_helper"

module Public
  class MonthlyActivityTest < ActiveSupport::TestCase
    setup do
      Civic::Jurisdiction.seed_defaults!
      @jurisdiction = Civic::Jurisdiction.default
      @period_start = Date.new(2026, 5, 1)
      @period_end = Date.new(2026, 5, 31)
    end

    # --- decisions ----------------------------------------------------------

    test "includes matters with passed_date inside the window" do
      matter = Civic::Matter.create!(
        legistar_matter_id: 70_001,
        matter_file: "26-100",
        passed_date: Date.new(2026, 5, 15),
        source_system: "legistar.sanjose",
      )

      result = build_activity.decisions

      assert_equal 1, result.size
      assert_equal matter, result.first.matter
      assert_equal Date.new(2026, 5, 15), result.first.passed_date
    end

    test "excludes matters with passed_date before the window" do
      Civic::Matter.create!(
        legistar_matter_id: 70_011,
        matter_file: "26-101",
        passed_date: Date.new(2026, 4, 30),
        source_system: "legistar.sanjose",
      )

      assert_empty build_activity.decisions
    end

    test "excludes matters with passed_date after the window" do
      Civic::Matter.create!(
        legistar_matter_id: 70_012,
        matter_file: "26-102",
        passed_date: Date.new(2026, 6, 1),
        source_system: "legistar.sanjose",
      )

      assert_empty build_activity.decisions
    end

    test "excludes matters with passed_date nil" do
      Civic::Matter.create!(
        legistar_matter_id: 70_013,
        matter_file: "26-103",
        passed_date: nil,
        source_system: "legistar.sanjose",
      )

      assert_empty build_activity.decisions
    end

    test "decisions ordered newest passed_date first" do
      matter_earlier = Civic::Matter.create!(
        legistar_matter_id: 70_100,
        matter_file: "26-200",
        passed_date: Date.new(2026, 5, 5),
        source_system: "legistar.sanjose",
      )
      matter_later = Civic::Matter.create!(
        legistar_matter_id: 70_101,
        matter_file: "26-201",
        passed_date: Date.new(2026, 5, 20),
        source_system: "legistar.sanjose",
      )

      result = build_activity.decisions

      assert_equal 2, result.size
      assert_equal matter_later, result.first.matter
      assert_equal matter_earlier, result.second.matter
    end

    test "primary_theme_label reflects rank-1 theme label" do
      matter = Civic::Matter.create!(
        legistar_matter_id: 70_200,
        matter_file: "26-300",
        passed_date: Date.new(2026, 5, 10),
        source_system: "legistar.sanjose",
      )
      matter.themes.create!(theme_slug: "housing", rank: 1)

      result = build_activity.decisions

      assert_equal "Housing", result.first.primary_theme_label
    end

    test "primary_theme_label is nil when matter has no themes" do
      Civic::Matter.create!(
        legistar_matter_id: 70_201,
        matter_file: "26-301",
        passed_date: Date.new(2026, 5, 10),
        source_system: "legistar.sanjose",
      )

      result = build_activity.decisions

      assert_nil result.first.primary_theme_label
    end

    # --- introduced ---------------------------------------------------------

    test "includes matters with intro_date inside the window" do
      matter = Civic::Matter.create!(
        legistar_matter_id: 70_300,
        matter_file: "26-400",
        intro_date: Date.new(2026, 5, 12),
        source_system: "legistar.sanjose",
      )

      result = build_activity.introduced

      assert_equal 1, result.size
      assert_equal matter, result.first.matter
      assert_equal Date.new(2026, 5, 12), result.first.intro_date
    end

    test "introduced ordered newest intro_date first" do
      matter_earlier = Civic::Matter.create!(
        legistar_matter_id: 70_400,
        matter_file: "26-500",
        intro_date: Date.new(2026, 5, 3),
        source_system: "legistar.sanjose",
      )
      matter_later = Civic::Matter.create!(
        legistar_matter_id: 70_401,
        matter_file: "26-501",
        intro_date: Date.new(2026, 5, 25),
        source_system: "legistar.sanjose",
      )

      result = build_activity.introduced

      assert_equal 2, result.size
      assert_equal matter_later, result.first.matter
      assert_equal matter_earlier, result.second.matter
    end

    test "introduced primary_theme_label reflects rank-1 theme" do
      matter = Civic::Matter.create!(
        legistar_matter_id: 70_500,
        matter_file: "26-600",
        intro_date: Date.new(2026, 5, 14),
        source_system: "legistar.sanjose",
      )
      matter.themes.create!(theme_slug: "housing", rank: 1)

      result = build_activity.introduced

      assert_equal "Housing", result.first.primary_theme_label
    end

    # --- jurisdiction scoping -----------------------------------------------

    test "decisions excludes matters from a different jurisdiction" do
      sjusd = Civic::Jurisdiction.find_by!(slug: "sjusd")
      Civic::Matter.create!(
        source_matter_id: "OTHER-1",
        matter_file: "OTHER-1",
        passed_date: Date.new(2026, 5, 10),
        source_system: "simbli.sjusd",
        civic_jurisdiction: sjusd,
      )

      assert_empty build_activity.decisions
    end

    private

    def build_activity
      MonthlyActivity.new(
        jurisdiction: @jurisdiction,
        period_start: @period_start,
        period_end: @period_end,
      )
    end
  end
end
