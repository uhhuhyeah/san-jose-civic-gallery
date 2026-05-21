module Ingestion
  module Simbli
    # Upserts a Simbli meeting as a jurisdiction-scoped Civic::Event. The agenda
    # tree response is recorded as the meeting's source snapshot. event_date is
    # supplied by the caller (sourced from the listing row), since the agenda
    # payload does not carry it.
    class PersistMeeting
      Ids = ::Simbli::Identifiers

      def self.call(school_id:, mid:, meeting_title:, meeting_type:, event_date:, request_url:, fetched_at:, http_status:, response_sha256:, payload:)
        source_id = Ids.event_source_id(school_id:, mid:)

        snapshot = RecordSourceSnapshot.call(
          source_system: Ids::SOURCE_SYSTEM,
          resource_type: "meeting",
          source_id: source_id,
          request_url: request_url,
          fetched_at: fetched_at,
          http_status: http_status,
          response_sha256: response_sha256,
          payload: payload
        )

        event = Civic::Event.find_or_initialize_by(
          source_system: Ids::SOURCE_SYSTEM,
          source_event_id: source_id
        )
        event.assign_attributes(
          body_name: Ids::DEFAULT_BODY_NAME,
          title: meeting_title,
          source_meeting_type: meeting_type,
          event_date: event_date,
          in_site_url: Ids.meeting_url(school_id:, mid:),
          source_present: true,
          source_missing_at: nil,
          last_synced_at: fetched_at,
          raw_source_digest: response_sha256,
          last_source_snapshot_id: snapshot.id
        )
        event.save!

        [ event, snapshot ]
      end
    end
  end
end
