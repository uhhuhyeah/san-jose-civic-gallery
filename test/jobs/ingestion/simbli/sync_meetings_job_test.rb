require "test_helper"

module Ingestion
  module Simbli
    class SyncMeetingsJobTest < ActiveSupport::TestCase
      test "enqueues on the simbli_ingestion queue" do
        assert_enqueued_with(queue: "simbli_ingestion") do
          SyncMeetingsJob.perform_later(limit: 5)
        end
      end

      test "discovers meetings and fans out per-meeting jobs with an injected client" do
        listing = JSON.parse(file_fixture("simbli/meeting_listing.json").read)

        assert_enqueued_jobs 2, only: SyncMeetingJob do
          SyncMeetingsJob.perform_now(limit: 5, client: FakeClient.new(listing))
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
