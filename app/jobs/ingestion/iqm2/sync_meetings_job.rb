module Ingestion
  module Iqm2
    # Discovery entry point for recurring IQM2 ingestion; fans out per-meeting
    # jobs on the isolated iqm2_ingestion queue. Client injectable for tests.
    class SyncMeetingsJob < ApplicationJob
      queue_as :iqm2_ingestion

      def perform(limit: nil, client: nil)
        SyncMeetings.call(client: client || ::Iqm2::Client.new, limit: limit)
      end
    end
  end
end
