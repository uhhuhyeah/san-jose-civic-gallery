require "test_helper"

module Civic
  class RoundupPeriodTest < ActiveSupport::TestCase
    setup do
      Civic::Jurisdiction.seed_defaults!
      @jurisdiction = Civic::Jurisdiction.default
    end

    test ".for_month creates a record with correct dates and label" do
      record = Civic::RoundupPeriod.for_month(jurisdiction: @jurisdiction, year: 2026, month: 5)

      assert_equal Date.new(2026, 5, 1), record.period_start
      assert_equal Date.new(2026, 5, 31), record.period_end
      assert_equal "May 2026", record.label
    end

    test ".for_month is idempotent" do
      first = Civic::RoundupPeriod.for_month(jurisdiction: @jurisdiction, year: 2026, month: 5)
      count_before = Civic::RoundupPeriod.count

      second = Civic::RoundupPeriod.for_month(jurisdiction: @jurisdiction, year: 2026, month: 5)

      assert_equal first, second
      assert_equal count_before, Civic::RoundupPeriod.count
    end

    test "#to_param returns period_start as YYYY-MM" do
      record = Civic::RoundupPeriod.for_month(jurisdiction: @jurisdiction, year: 2026, month: 5)

      assert_equal "2026-05", record.to_param
    end

    test "uniqueness validation prevents duplicate jurisdiction + start + end" do
      Civic::RoundupPeriod.for_month(jurisdiction: @jurisdiction, year: 2026, month: 5)

      duplicate = Civic::RoundupPeriod.new(
        civic_jurisdiction: @jurisdiction,
        period_start: Date.new(2026, 5, 1),
        period_end: Date.new(2026, 5, 31),
        label: "May 2026"
      )

      assert_not duplicate.valid?
    end

    test ".for_jurisdiction returns records for that jurisdiction" do
      record = Civic::RoundupPeriod.for_month(jurisdiction: @jurisdiction, year: 2026, month: 5)

      results = Civic::RoundupPeriod.for_jurisdiction(@jurisdiction)

      assert_includes results, record
    end
  end
end
