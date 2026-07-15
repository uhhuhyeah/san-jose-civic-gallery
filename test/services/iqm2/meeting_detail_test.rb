require "test_helper"

module Iqm2
  class MeetingDetailTest < ActiveSupport::TestCase
    setup do
      @payload = file_fixture("iqm2/meeting_detail.html").read
    end

    test "parse extracts meeting and agenda items" do
      result = MeetingDetail.parse(@payload)

      assert_not_nil result
      assert_not_nil result.meeting
      assert_not_nil result.agenda_items
    end

    test "meeting details are correct" do
      result = MeetingDetail.parse(@payload)
      meeting = result.meeting

      assert_equal "17599", meeting.meeting_id
      assert_equal "Board of Supervisors", meeting.body_name
      assert_equal "Regular Meeting", meeting.meeting_type
      assert_equal Date.new(2026, 6, 23), meeting.event_date
      assert_includes meeting.location, "70 West Hedding Street"
    end

    test "agenda items count is 171" do
      result = MeetingDetail.parse(@payload)
      assert_equal 171, result.agenda_items.size
    end

    test "item 129725 has correct details and attachment" do
      result = MeetingDetail.parse(@payload)
      inv = result.agenda_items.find { |i| i.legifile_id == "129725" }

      assert_not_nil inv
      assert_equal "3", inv.item_number
      assert inv.title.start_with?("Invocation by Dr. Melissa Urbain")
      assert_equal 1, inv.attachments.size

      attachment = inv.attachments.first
      assert_equal "30", attachment.type
      assert_equal "228428", attachment.file_id
      assert_equal "Commendation/Proclamation Printout", attachment.title
      assert_equal "https://sccgov.iqm2.com/Citizens/FileOpen.aspx?Type=30&ID=228428&MeetingID=17599", attachment.url
    end

    test "item 129384 has correct details" do
      result = MeetingDetail.parse(@payload)
      mem = result.agenda_items.find { |i| i.legifile_id == "129384" }

      assert_not_nil mem
      assert_equal "a", mem.item_number
      assert mem.title.include?("Adjourn in honor and memory of Paris Shatel Morales")
    end

    test "raises ParseError when MeetingDetail table is missing" do
      assert_raises(MeetingDetail::ParseError) do
        MeetingDetail.parse("<html><body>Access Denied</body></html>")
      end
    end

    # Net::HTTP delivers the agenda body as ASCII-8BIT; parsing must not depend
    # on Nokogiri sniffing the charset (see MeetingCalendar for the utf-16 trap).
    test "parses an agenda body delivered as ASCII-8BIT" do
      result = MeetingDetail.parse(@payload.dup.force_encoding("ASCII-8BIT"))
      assert_equal 171, result.agenda_items.size
    end
  end
end
