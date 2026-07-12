module Ingestion
  module Iqm2
    # Upserts an IQM2 meeting as a jurisdiction-scoped Civic::Event and records
    # the meeting-detail response as its source snapshot. Jurisdiction is derived
    # from source_system by JurisdictionScoped.
    class PersistMeeting
      Ids = ::Iqm2::Identifiers

      def self.call(meeting_id:, body_name:, meeting_type:, event_date:, location:, request_url:, fetched_at:, http_status:, response_sha256:, payload:)
        source_id = Ids.event_source_id(meeting_id: meeting_id)

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
          body_name: body_name,
          source_meeting_type: meeting_type,
          event_date: event_date,
          location_name: location,
          in_site_url: Ids.meeting_detail_url(meeting_id: meeting_id),
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
