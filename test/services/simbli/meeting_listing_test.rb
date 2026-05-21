require "test_helper"

module Simbli
  class MeetingListingTest < ActiveSupport::TestCase
    test "extracts school_id, mid, and meeting title, skipping non-meeting links" do
      payload = JSON.parse(file_fixture("simbli/meeting_listing.json").read)
      meetings = MeetingListing.parse(payload)

      assert_equal 2, meetings.size
      assert_equal "36030421", meetings.first.school_id
      assert_equal "57394", meetings.first.mid
      assert_equal "Regular Session Board Meeting", meetings.first.meeting_title
      assert_equal "65707", meetings.second.mid
    end
  end
end
