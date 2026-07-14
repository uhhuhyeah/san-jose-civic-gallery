require "test_helper"

module Iqm2
  class IdentifiersTest < ActiveSupport::TestCase
    test "event_source_id returns meeting id as string" do
      assert_equal "17599", Identifiers.event_source_id(meeting_id: "17599")
    end

    test "event_item_source_id returns meeting:legifile composite id" do
      assert_equal "17599:129725", Identifiers.event_item_source_id(meeting_id: "17599", legifile_id: "129725")
    end

    test "matter_source_id returns legifile id as string" do
      assert_equal "129725", Identifiers.matter_source_id(legifile_id: "129725")
    end

    test "attachment_source_id returns type:file_id composite id" do
      assert_equal "30:228428", Identifiers.attachment_source_id(type: "30", file_id: "228428")
    end

    test "meeting_detail_url builds correct URL" do
      expected = "https://sccgov.iqm2.com/Citizens/Detail_Meeting.aspx?ID=17599"
      assert_equal expected, Identifiers.meeting_detail_url(meeting_id: "17599")
    end

    test "file_open_url builds correct URL with meeting_id" do
      expected = "https://sccgov.iqm2.com/Citizens/FileOpen.aspx?Type=30&ID=228428&MeetingID=17599"
      assert_equal expected, Identifiers.file_open_url(type: "30", file_id: "228428", meeting_id: "17599")
    end

    test "file_open_url builds correct URL without meeting_id" do
      expected = "https://sccgov.iqm2.com/Citizens/FileOpen.aspx?Type=14&ID=15796"
      assert_equal expected, Identifiers.file_open_url(type: "14", file_id: "15796")
    end

    test "absolute_url resolves relative href" do
      expected = "https://sccgov.iqm2.com/Citizens/FileOpen.aspx?Type=30&ID=228428"
      assert_equal expected, Identifiers.absolute_url("FileOpen.aspx?Type=30&ID=228428")
    end
  end
end
