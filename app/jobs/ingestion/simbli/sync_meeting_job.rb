module Ingestion
  module Simbli
    # Runs a single Simbli meeting sync on the isolated, low-concurrency
    # browser queue. The client is injectable for tests; production uses a real
    # browser-backed Simbli::Client.
    class SyncMeetingJob < ApplicationJob
      queue_as :simbli_ingestion

      def perform(school_id:, mid:, meeting_title:, meeting_type:, event_date:, client: nil)
        SyncMeeting.call(
          school_id: school_id,
          mid: mid,
          meeting_title: meeting_title,
          meeting_type: meeting_type,
          event_date: event_date,
          client: client || ::Simbli::Client.new(school_id: school_id)
        )
      end
    end
  end
end
