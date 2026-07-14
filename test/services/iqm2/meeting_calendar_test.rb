require "test_helper"

module Iqm2
  class MeetingCalendarTest < ActiveSupport::TestCase
    setup do
      @payload = file_fixture("iqm2/meeting_calendar.xml").read
    end

    test "parse returns 216 meeting refs (webcast-only entries are skipped)" do
      refs = MeetingCalendar.parse(@payload)
      assert_equal 216, refs.size
    end

    test "parse raises on a blocked or unrecognizable response instead of returning empty" do
      assert_raises(MeetingCalendar::ParseError) { MeetingCalendar.parse("") }
      assert_raises(MeetingCalendar::ParseError) { MeetingCalendar.parse("<html><body>Access Denied</body></html>") }
      assert_raises(MeetingCalendar::ParseError) { MeetingCalendar.parse(nil) }
    end

    test "first ref is HIV Commission agenda for Jul 16, 2026" do
      refs = MeetingCalendar.parse(@payload)
      first = refs.first

      assert_equal "18326", first.meeting_id
      assert_equal "HIV Commission", first.body_name
      assert_equal "Agenda", first.media_type
      assert_equal Date.new(2026, 7, 16), first.event_date
      assert_equal "15853", first.agenda_file_id
      assert_equal 2026, first.published_at.year
      assert_kind_of Time, first.published_at
    end

    test "Board of Supervisors agenda ref exists with correct details" do
      refs = MeetingCalendar.parse(@payload)
      bos = refs.find { |r| r.meeting_id == "17599" && r.media_type == "Agenda" }

      assert_not_nil bos
      assert_equal "Board of Supervisors", bos.body_name
      assert_equal Date.new(2026, 6, 23), bos.event_date
      assert_equal "15796", bos.agenda_file_id
    end

    test "no webcast refs survive parsing" do
      refs = MeetingCalendar.parse(@payload)
      assert_empty refs.select { |r| r.media_type == "Webcast" }
    end

    test "body names with commas are preserved" do
      refs = MeetingCalendar.parse(@payload)
      assert refs.any? { |r| r.body_name == "Housing, Land Use, Environment, and Transportation Committee" }
    end
  end
end
