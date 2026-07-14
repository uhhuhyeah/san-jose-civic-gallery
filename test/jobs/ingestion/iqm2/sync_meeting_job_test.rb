require "test_helper"

module Ingestion
  module Iqm2
    class SyncMeetingJobTest < ActiveSupport::TestCase
      test "enqueues on the iqm2_ingestion queue" do
        assert_enqueued_with(queue: "iqm2_ingestion") do
          SyncMeetingJob.perform_later(meeting_id: "8001")
        end
      end

      test "runs the sync with an injected client" do
        html = file_fixture("iqm2/sync_meeting_detail.html").read

        SyncMeetingJob.perform_now(
          meeting_id: "8001",
          event_date: Date.new(2026, 6, 23),
          client: FakeClient.new(html)
        )

        assert Civic::Event.exists?(source_system: "iqm2.sccgov", source_event_id: "8001")
      end

      class FakeClient
        def initialize(html)
          @html = html
        end

        def meeting_detail(meeting_id:)
          {
            request_url: "https://example.test/meeting/#{meeting_id}",
            status: 200,
            fetched_at: Time.current,
            response_sha256: "detail-sha",
            payload: @html
          }
        end
      end
    end
  end
end
