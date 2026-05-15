module Ingestion
  class PersistMatter
    def self.call(matter_payload:, source_system:, request_url:, fetched_at:, http_status:, response_sha256:)
      snapshot = RecordSourceSnapshot.call(
        source_system: source_system,
        resource_type: "matter",
        source_id: matter_payload.fetch("MatterId").to_s,
        request_url: request_url,
        fetched_at: fetched_at,
        http_status: http_status,
        response_sha256: response_sha256,
        payload: matter_payload
      )

      matter = Civic::Matter.find_or_initialize_by(
        source_system: source_system,
        legistar_matter_id: matter_payload.fetch("MatterId")
      )
      matter.assign_attributes(attributes_from(matter_payload, fetched_at:, response_sha256:, snapshot:))
      matter.save!

      [ matter, snapshot ]
    end

    def self.attributes_from(matter_payload, fetched_at:, response_sha256:, snapshot:)
      {
        matter_file: matter_payload["MatterFile"],
        body_name: matter_payload["MatterBodyName"],
        title: matter_payload["MatterTitle"],
        name: matter_payload["MatterName"],
        matter_type_name: matter_payload["MatterTypeName"],
        matter_status_name: matter_payload["MatterStatusName"],
        requester: matter_payload["MatterRequester"],
        intro_date: matter_payload["MatterIntroDate"],
        agenda_date: matter_payload["MatterAgendaDate"],
        passed_date: matter_payload["MatterPassedDate"],
        enactment_date: matter_payload["MatterEnactmentDate"],
        enactment_number: matter_payload["MatterEnactmentNumber"],
        version: matter_payload["MatterVersion"],
        notes: matter_payload["MatterNotes"],
        source_last_modified_at: matter_payload["MatterLastModifiedUtc"],
        last_synced_at: fetched_at,
        raw_source_digest: response_sha256,
        last_source_snapshot_id: snapshot.id
      }
    end
    private_class_method :attributes_from
  end
end
