module Ingestion
  module Iqm2
    # Discovery entry point for recurring IQM2 ingestion: fetch the RSS calendar
    # and fan out a per-meeting SyncMeetingJob for each in-scope agenda meeting.
    # Scope starts at the Board of Supervisors only (the county exposes dozens of
    # low-volume bodies); widen IN_SCOPE_BODIES deliberately. Runs on the isolated
    # low-concurrency iqm2_ingestion queue.
    class SyncMeetings
      IN_SCOPE_BODIES = [ "Board of Supervisors" ].freeze

      def self.call(client:, limit: nil, body_names: IN_SCOPE_BODIES)
        refs = ::Iqm2::MeetingCalendar.parse(client.meeting_listing[:payload])
        refs = refs.select { |ref| ref.media_type == "Agenda" && ref.meeting_id.present? && body_names.include?(ref.body_name) }
        refs = refs.first(limit) if limit

        enqueued = []
        refs.each do |ref|
          SyncMeetingJob.perform_later(meeting_id: ref.meeting_id, event_date: ref.event_date)
          enqueued << ref.meeting_id
        end

        Rails.logger.info("Ingestion::Iqm2::SyncMeetings enqueued #{enqueued.size} meeting syncs (limit=#{limit || 'none'})")
        enqueued
      end
    end
  end
end
