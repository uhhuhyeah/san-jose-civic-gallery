module Ingestion
  module Simbli
    # Discovery entry point for recurring SJUSD ingestion: fetches the listing
    # and fans out per-meeting jobs, all on the isolated simbli_ingestion queue.
    # The client is injectable for tests; production uses a real browser-backed
    # Simbli::Client.
    class SyncMeetingsJob < ApplicationJob
      queue_as :simbli_ingestion

      def perform(limit: nil, school_id: ::Simbli::Client::DEFAULT_SCHOOL_ID, client: nil)
        SyncMeetings.call(
          client: client || ::Simbli::Client.new(school_id: school_id),
          limit: limit
        )
      end
    end
  end
end
