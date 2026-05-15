module Ingestion
  class PersistEventItem
    def self.call(event:, event_item_payload:, request_url:, fetched_at:, http_status:, response_sha256:, matter: nil)
      snapshot = SourceSnapshot.create!(
        source_system: "legistar",
        resource_type: "event_item",
        source_id: event_item_payload.fetch("EventItemId").to_s,
        request_url: request_url,
        fetched_at: fetched_at,
        http_status: http_status,
        response_sha256: response_sha256,
        payload: event_item_payload
      )

      event_item = Civic::EventItem.find_or_initialize_by(legistar_event_item_id: event_item_payload.fetch("EventItemId"))
      event_item.assign_attributes(attributes_from(event:, matter:, event_item_payload:, fetched_at:, response_sha256:))
      event_item.save!

      [ event_item, snapshot ]
    end

    def self.attributes_from(event:, matter:, event_item_payload:, fetched_at:, response_sha256:)
      {
        civic_event_id: event.id,
        civic_matter_id: matter&.id,
        agenda_sequence: event_item_payload["EventItemAgendaSequence"],
        minutes_sequence: event_item_payload["EventItemMinutesSequence"],
        agenda_number: event_item_payload["EventItemAgendaNumber"],
        title: event_item_payload["EventItemTitle"],
        agenda_note: event_item_payload["EventItemAgendaNote"],
        minutes_note: event_item_payload["EventItemMinutesNote"],
        action_name: event_item_payload["EventItemActionName"],
        action_text: event_item_payload["EventItemActionText"],
        passed_flag_name: event_item_payload["EventItemPassedFlagName"],
        roll_call_flag: event_item_payload["EventItemRollCallFlag"],
        consent: event_item_payload["EventItemConsent"],
        tally: event_item_payload["EventItemTally"],
        matter_id: event_item_payload["EventItemMatterId"],
        matter_file: event_item_payload["EventItemMatterFile"],
        matter_name: event_item_payload["EventItemMatterName"],
        matter_type: event_item_payload["EventItemMatterType"],
        matter_status: event_item_payload["EventItemMatterStatus"],
        source_last_modified_at: event_item_payload["EventItemLastModifiedUtc"],
        last_synced_at: fetched_at,
        raw_source_digest: response_sha256
      }
    end
    private_class_method :attributes_from
  end
end
