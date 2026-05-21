require "test_helper"

module Simbli
  class MeetingListingTest < ActiveSupport::TestCase
    setup do
      @payload = JSON.parse(file_fixture("simbli/meeting_listing.json").read)
    end

    test "extracts ids, title, type, and date, skipping non-meeting rows" do
      meetings = MeetingListing.parse(@payload)

      assert_equal 2, meetings.size
      first = meetings.first
      assert_equal "36030421", first.school_id
      assert_equal "57394", first.mid
      assert_equal "Regular Session Board Meeting", first.meeting_title
      assert_equal "Regular Session Board Meeting", first.meeting_type
      assert_equal Date.new(2026, 4, 23), first.event_date
    end

    test "keeps title and type distinct for special rows" do
      financing = MeetingListing.parse(@payload).find { |m| m.mid == "65707" }

      assert_equal "Financing Corporation Annual Meeting", financing.meeting_title
      assert_equal "Special Session Board Meeting", financing.meeting_type
      assert_equal Date.new(2026, 3, 26), financing.event_date
    end

    test "matches columns by header keyword regardless of order or wording" do
      rows = [ {
        "onclick" => "ViewMeeting(\"36030421\",\"900\")",
        "cells" => { "Meeting Type" => "Study Session", "When (Date/Time)" => "1/2/2026 9:00 AM", "Title" => "Budget Study" }
      } ]

      meeting = MeetingListing.parse(rows).first
      assert_equal "Budget Study", meeting.meeting_title
      assert_equal "Study Session", meeting.meeting_type
      assert_equal Date.new(2026, 1, 2), meeting.event_date
    end

    test "yields a nil date when no date can be parsed" do
      rows = [ { "onclick" => "ViewMeeting(\"36030421\",\"901\")", "cells" => { "Meeting Title" => "TBD" } } ]

      assert_nil MeetingListing.parse(rows).first.event_date
    end
  end
end
