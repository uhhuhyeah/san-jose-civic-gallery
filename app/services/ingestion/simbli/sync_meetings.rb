module Ingestion
  module Simbli
    # Discovers SJUSD meetings from the Simbli listing and enqueues a per-meeting
    # SyncMeetingJob for each (optionally capped by limit). Fanning out to one
    # job per meeting keeps each meeting's browser fetch isolated and
    # individually retryable on the low-concurrency simbli_ingestion queue.
    #
    # Meetings whose listing row has no parseable date are skipped and logged,
    # since event_date is required and a missing date signals a listing-parse
    # gap worth surfacing.
    class SyncMeetings
      def self.call(client:, limit: nil)
        meetings = ::Simbli::MeetingListing.parse(client.meeting_listing[:payload])
        meetings = meetings.first(limit) if limit

        enqueued = []
        meetings.each do |meeting|
          if meeting.event_date.nil?
            Rails.logger.warn("Ingestion::Simbli::SyncMeetings skipping MID #{meeting.mid}: no parseable date")
            next
          end

          SyncMeetingJob.perform_later(
            school_id: meeting.school_id,
            mid: meeting.mid,
            meeting_title: meeting.meeting_title,
            meeting_type: meeting.meeting_type,
            event_date: meeting.event_date
          )
          enqueued << meeting.mid
        end

        Rails.logger.info("Ingestion::Simbli::SyncMeetings enqueued #{enqueued.size} meeting syncs (limit=#{limit || 'none'})")
        enqueued
      end
    end
  end
end
