require "test_helper"

module Ingestion
  module Simbli
    class SyncMeetingsTest < ActiveSupport::TestCase
      setup do
        @listing = JSON.parse(file_fixture("simbli/meeting_listing.json").read)
      end

      test "enqueues a per-meeting job for each discovered meeting" do
        assert_enqueued_jobs 2, only: SyncMeetingJob do
          SyncMeetings.call(client: FakeClient.new(@listing))
        end
      end

      test "passes the parsed descriptor (title, type, date) to the job" do
        assert_enqueued_with(
          job: SyncMeetingJob,
          args: [ { school_id: "36030421", mid: "57394", meeting_title: "Regular Session Board Meeting", meeting_type: "Regular Session Board Meeting", event_date: Date.new(2026, 4, 23) } ]
        ) do
          SyncMeetings.call(client: FakeClient.new(@listing))
        end
      end

      test "respects the limit" do
        enqueued = nil
        assert_enqueued_jobs 1, only: SyncMeetingJob do
          enqueued = SyncMeetings.call(client: FakeClient.new(@listing), limit: 1)
        end
        assert_equal [ "57394" ], enqueued
      end

      test "skips meetings whose date cannot be parsed" do
        listing = { "rows" => [ { "onclick" => "ViewMeeting(\"36030421\",\"902\")", "cells" => { "Meeting Title" => "No date" } } ] }

        assert_no_enqueued_jobs only: SyncMeetingJob do
          assert_empty SyncMeetings.call(client: FakeClient.new(listing))
        end
      end

      class FakeClient
        def initialize(listing)
          @listing = listing
        end

        def meeting_listing
          { request_url: "https://example.test/listing", status: 200, fetched_at: Time.current, response_sha256: "listing-sha", payload: @listing }
        end
      end
    end
  end
end
