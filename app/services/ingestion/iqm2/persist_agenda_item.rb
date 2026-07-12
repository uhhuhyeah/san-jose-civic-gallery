module Ingestion
  module Iqm2
    # Upserts one IQM2 agenda item: a real Civic::Matter (a LegiFile is a global
    # legislative file, so the matter is keyed by the bare LegiFile id), the
    # Civic::EventItem linking the meeting to that matter, and each attachment as
    # Civic::MatterAttachment metadata (the FileOpen URL is stored as hyperlink;
    # the PDF download is a later step). All share the meeting's snapshot.
    class PersistAgendaItem
      Ids = ::Iqm2::Identifiers

      def self.call(event:, item:, meeting_id:, position:, snapshot:, fetched_at:, response_sha256:)
        matter = upsert_matter(event:, item:, snapshot:, fetched_at:, response_sha256:)
        event_item = upsert_event_item(event:, item:, meeting_id:, matter:, position:, snapshot:, fetched_at:, response_sha256:)

        seen_attachment_ids = item.attachments.each_with_index.map do |attachment, index|
          upsert_attachment(matter:, attachment:, sort_order: index, snapshot:, fetched_at:, response_sha256:)
          Ids.attachment_source_id(type: attachment.type, file_id: attachment.file_id)
        end

        [ event_item, seen_attachment_ids ]
      end

      def self.upsert_matter(event:, item:, snapshot:, fetched_at:, response_sha256:)
        matter = Civic::Matter.find_or_initialize_by(
          source_system: Ids::SOURCE_SYSTEM,
          source_matter_id: Ids.matter_source_id(legifile_id: item.legifile_id)
        )
        matter.assign_attributes(
          matter_file: Ids.matter_file(legifile_id: item.legifile_id),
          title: item.title,
          body_name: event.body_name,
          last_synced_at: fetched_at,
          raw_source_digest: response_sha256,
          last_source_snapshot_id: snapshot.id
        )
        matter.save!
        matter
      end
      private_class_method :upsert_matter

      def self.upsert_event_item(event:, item:, meeting_id:, matter:, position:, snapshot:, fetched_at:, response_sha256:)
        event_item = Civic::EventItem.find_or_initialize_by(
          source_system: Ids::SOURCE_SYSTEM,
          source_event_item_id: Ids.event_item_source_id(meeting_id: meeting_id, legifile_id: item.legifile_id)
        )
        event_item.assign_attributes(
          civic_event_id: event.id,
          civic_matter_id: matter.id,
          title: item.title,
          agenda_number: item.item_number,
          agenda_sequence: position,
          source_present: true,
          source_missing_at: nil,
          last_synced_at: fetched_at,
          raw_source_digest: response_sha256,
          last_source_snapshot_id: snapshot.id
        )
        event_item.save!
        event_item
      end
      private_class_method :upsert_event_item

      def self.upsert_attachment(matter:, attachment:, sort_order:, snapshot:, fetched_at:, response_sha256:)
        record = Civic::MatterAttachment.find_or_initialize_by(
          source_system: Ids::SOURCE_SYSTEM,
          source_attachment_id: Ids.attachment_source_id(type: attachment.type, file_id: attachment.file_id)
        )
        record.assign_attributes(
          civic_matter_id: matter.id,
          name: attachment.title,
          hyperlink: attachment.url,
          is_supporting_document: true,
          is_hyperlink: false,
          sort_order: sort_order,
          source_present: true,
          source_missing_at: nil,
          last_synced_at: fetched_at,
          raw_source_digest: response_sha256,
          last_source_snapshot_id: snapshot.id
        )
        record.save!
        enqueue_import(record)
        record
      end
      private_class_method :upsert_attachment

      # Unlike SJUSD (whose downloads are blocked), IQM2 serves attachment PDFs
      # directly, so hand each new attachment to the shared download ->
      # extraction -> summary pipeline. Only enqueue for attachments that have
      # not been imported yet: the FileOpen URL is stable, so a re-sync should
      # not re-download the whole agenda's PDFs. (The host is allowlisted in a
      # later change; until then the job would record a DisallowedHost error.)
      def self.enqueue_import(attachment)
        return if attachment.hyperlink.blank?
        return if attachment.imported?

        Documents::ImportMatterAttachmentFileJob.perform_later(attachment.id)
      end
      private_class_method :enqueue_import
    end
  end
end
