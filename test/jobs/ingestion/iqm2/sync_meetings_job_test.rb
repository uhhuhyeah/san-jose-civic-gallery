require "test_helper"

module Ingestion
  module Iqm2
    class SyncMeetingsJobTest < ActiveSupport::TestCase
      test "enqueues on the iqm2_ingestion queue" do
        assert_enqueued_with(queue: "iqm2_ingestion") do
          SyncMeetingsJob.perform_later(limit: 5)
        end
      end

      test "discovers meetings and fans out per-meeting jobs with an injected client" do
        @listing = file_fixture("iqm2/meeting_calendar.xml").read

        assert_enqueued_jobs(1, only: SyncMeetingJob) do
          SyncMeetingsJob.perform_now(limit: 1, client: FakeClient.new(@listing))
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
