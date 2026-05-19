require "test_helper"

module Ingestion
  class CoerceTest < ActiveSupport::TestCase
    test "date parses ISO strings" do
      assert_equal Date.new(2026, 5, 12), Coerce.date("2026-05-12T00:00:00", field: "EventDate")
    end

    test "date returns nil for blank values" do
      assert_nil Coerce.date(nil, field: "EventDate")
      assert_nil Coerce.date("", field: "EventDate")
    end

    test "date raises InvalidPayload with the field name for unparseable input" do
      error = assert_raises(Coerce::InvalidPayload) do
        Coerce.date("not-a-date", field: "EventDate")
      end
      assert_match(/EventDate/, error.message)
      assert_match(/not-a-date/, error.message)
    end

    test "datetime parses ISO strings and returns a Time" do
      result = Coerce.datetime("2026-05-15T18:30:00Z", field: "EventLastModifiedUtc")
      assert_kind_of ActiveSupport::TimeWithZone, result
      assert_equal Time.zone.parse("2026-05-15T18:30:00Z"), result
    end

    test "datetime returns nil for blank values" do
      assert_nil Coerce.datetime(nil, field: "x")
      assert_nil Coerce.datetime("", field: "x")
    end

    test "datetime raises InvalidPayload with the field name for unparseable input" do
      error = assert_raises(Coerce::InvalidPayload) do
        Coerce.datetime("not-a-datetime", field: "MatterLastModifiedUtc")
      end
      assert_match(/MatterLastModifiedUtc/, error.message)
    end
  end
end
