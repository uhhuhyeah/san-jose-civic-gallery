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
        listing = client.meeting_listing
        unless listing[:status] == 200
          raise ::Iqm2::Client::ResponseError, "IQM2 calendar returned HTTP #{listing[:status]}"
        end

        # MeetingCalendar raises on a blocked/unrecognizable payload, so a bad
        # response fails here instead of enqueuing zero meetings as a success.
        refs = ::Iqm2::MeetingCalendar.parse(listing[:payload])
        refs = refs.select { |ref| ref.media_type == "Agenda" && ref.meeting_id.present? && body_names.include?(ref.body_name) }
        refs = refs.first(limit) if limit

        enqueued = []
        refs.each do |ref|
          SyncMeetingJob.perform_later(meeting_id: ref.meeting_id, event_date: ref.event_date)
          enqueued << ref.meeting_id
        end

        Rails.logger.info("Ingestion::Iqm2::SyncMeetings enqueued #{enqueued.size} meeting syncs (limit=#{limit || 'none'})")
        enqueued
      rescue ::Iqm2::MeetingCalendar::ParseError
        log_unrecognizable_calendar_response(listing) if defined?(listing) && listing
        raise
      end

      def self.log_unrecognizable_calendar_response(listing)
        diagnostics = calendar_response_diagnostics(listing)

        Rails.logger.warn(
          {
            message: "Ingestion::Iqm2::SyncMeetings received an unrecognizable calendar response",
            iqm2_calendar_response: diagnostics
          }.to_json
        )

        Sentry.set_context("iqm2_calendar_response", diagnostics) if defined?(Sentry)
      end
      private_class_method :log_unrecognizable_calendar_response

      def self.calendar_response_diagnostics(listing)
        payload = listing[:payload].to_s
        text = payload.scrub
        normalized_text = text.gsub(/\s+/, " ").strip

        {
          request_url: listing[:request_url],
          http_status: listing[:status],
          response_sha256: listing[:response_sha256],
          payload_bytes: payload.bytesize,
          text_preview: normalized_text.first(500),
          html_title: text[%r{<title[^>]*>(.*?)</title>}im, 1]&.gsub(/\s+/, " ")&.strip,
          first_heading: text[%r{<h[1-6][^>]*>(.*?)</h[1-6]>}im, 1]&.gsub(/<[^>]+>/, " ")&.gsub(/\s+/, " ")&.strip,
          signals: {
            meeting_calendar: text.match?(/Meeting Calendar/i),
            detail_meeting_link: text.match?(/Detail_Meeting\.aspx\?ID=/i),
            access_denied: text.match?(/Access Denied/i),
            captcha: text.match?(/captcha/i),
            error: text.match?(/\berror\b/i)
          }
        }
      end
      private_class_method :calendar_response_diagnostics
    end
  end
end
