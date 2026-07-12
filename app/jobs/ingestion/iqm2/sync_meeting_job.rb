module Ingestion
  module Iqm2
    # Runs a single IQM2 meeting sync on the isolated, low-concurrency
    # iqm2_ingestion queue. The client is injectable for tests.
    class SyncMeetingJob < ApplicationJob
      queue_as :iqm2_ingestion

      def perform(meeting_id:, event_date: nil, client: nil)
        SyncMeeting.call(
          meeting_id: meeting_id,
          event_date: event_date,
          client: client || ::Iqm2::Client.new
        )
      end
    end
  end
end
