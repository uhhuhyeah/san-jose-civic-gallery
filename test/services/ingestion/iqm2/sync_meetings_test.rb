require "test_helper"

module Ingestion
  module Iqm2
    class SyncMeetingsTest < ActiveSupport::TestCase
      setup do
        @listing = file_fixture("iqm2/meeting_calendar.xml").read
      end

      test "enqueues only in-scope Board of Supervisors agenda meetings" do
        enqueued = SyncMeetings.call(client: FakeClient.new(@listing))

        assert enqueued.include?("17599")
        assert enqueued.all? { |id| id.present? }

        # Verify a NON-BoS meeting id is not enqueued
        assert_not enqueued.include?("18326")
      end

      test "respects the limit" do
        assert_enqueued_jobs 1, only: SyncMeetingJob do
          enqueued = SyncMeetings.call(client: FakeClient.new(@listing), limit: 1)
          assert_equal 1, enqueued.size
        end
      end

      test "passes meeting_id and event_date to the job" do
        assert_enqueued_with(
          job: SyncMeetingJob,
          args: [ { meeting_id: "17599", event_date: Date.new(2026, 6, 23) } ]
        ) do
          SyncMeetings.call(client: FakeClient.new(@listing))
        end
      end

      class FakeClient
        def initialize(listing)
          @listing = listing
        end

        def meeting_listing
          {
            request_url: "https://example.test/listing",
            status: 200,
            fetched_at: Time.current,
            response_sha256: "listing-sha",
            payload: @listing
          }
        end
      end
    end
  end
end
