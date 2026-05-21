module Ingestion
  module Simbli
    # Upserts one Simbli agenda item as a Civic::EventItem under its meeting.
    # Agenda items derive from the meeting's agenda tree, so they share the
    # meeting's source snapshot rather than recording their own.
    class PersistAgendaItem
      Ids = ::Simbli::Identifiers

      def self.call(event:, item:, school_id:, mid:, snapshot:, fetched_at:, response_sha256:)
        source_id = Ids.event_item_source_id(school_id:, mid:, agenda_id: item.agenda_id)

        event_item = Civic::EventItem.find_or_initialize_by(
          source_system: Ids::SOURCE_SYSTEM,
          source_event_item_id: source_id
        )
        event_item.assign_attributes(
          civic_event_id: event.id,
          title: item.title,
          agenda_sequence: item.position,
          source_present: true,
          source_missing_at: nil,
          last_synced_at: fetched_at,
          raw_source_digest: response_sha256,
          last_source_snapshot_id: snapshot.id
        )
        event_item.save!

        event_item
      end
    end
  end
end
