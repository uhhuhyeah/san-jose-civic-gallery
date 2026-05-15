module Ingestion
  class PersistEvent
    def self.call(event_payload:, source_system:, request_url:, fetched_at:, http_status:, response_sha256:)
      snapshot = SourceSnapshot.create!(
        source_system: source_system,
        resource_type: "event",
        source_id: event_payload.fetch("EventId").to_s,
        request_url: request_url,
        fetched_at: fetched_at,
        http_status: http_status,
        response_sha256: response_sha256,
        payload: event_payload
      )

      event = Civic::Event.find_or_initialize_by(
        source_system: source_system,
        legistar_event_id: event_payload.fetch("EventId")
      )
      event.assign_attributes(attributes_from(event_payload, fetched_at:, response_sha256:, snapshot:))
      event.save!

      [ event, snapshot ]
    end

    def self.attributes_from(event_payload, fetched_at:, response_sha256:, snapshot:)
      {
        body_name: event_payload["EventBodyName"],
        title: event_payload["EventTitle"],
        event_date: event_payload["EventDate"],
        event_time: event_payload["EventTime"],
        location_name: event_payload["EventLocation"],
        agenda_status_name: event_payload["EventAgendaStatusName"],
        minutes_status_name: event_payload["EventMinutesStatusName"],
        in_site_url: event_payload["EventInSiteURL"],
        agenda_file_uri: event_payload["EventAgendaFile"],
        minutes_file_uri: event_payload["EventMinutesFile"],
        source_last_modified_at: event_payload["EventLastModifiedUtc"],
        source_present: true,
        source_missing_at: nil,
        last_synced_at: fetched_at,
        raw_source_digest: response_sha256,
        last_source_snapshot_id: snapshot.id
      }
    end
    private_class_method :attributes_from
  end
end
