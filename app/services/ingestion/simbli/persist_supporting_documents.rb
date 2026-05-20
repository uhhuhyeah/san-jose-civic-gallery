module Ingestion
  module Simbli
    # Persists an agenda item's supporting documents. Simbli has no Legistar-
    # style "matter", so we create one synthetic Civic::Matter per agenda item
    # that carries documents, link the event item to it, and attach each
    # document as a Civic::MatterAttachment. The original Attachment.aspx URL is
    # stored as the hyperlink for manual recovery when downloads are blocked.
    class PersistSupportingDocuments
      Ids = ::Simbli::Identifiers

      def self.call(event_item:, school_id:, mid:, agenda_id:, item_title:, attachments:, request_url:, fetched_at:, http_status:, response_sha256:, payload:)
        snapshot = RecordSourceSnapshot.call(
          source_system: Ids::SOURCE_SYSTEM,
          resource_type: "supporting_documents",
          source_id: Ids.event_item_source_id(school_id:, mid:, agenda_id:),
          request_url: request_url,
          fetched_at: fetched_at,
          http_status: http_status,
          response_sha256: response_sha256,
          payload: payload
        )

        matter = upsert_matter(school_id:, mid:, agenda_id:, item_title:, fetched_at:, response_sha256:, snapshot:)
        event_item.update!(civic_matter_id: matter.id)

        attachments.each do |doc|
          upsert_attachment(matter:, school_id:, mid:, doc:, fetched_at:, response_sha256:, snapshot:)
        end

        matter
      end

      def self.upsert_matter(school_id:, mid:, agenda_id:, item_title:, fetched_at:, response_sha256:, snapshot:)
        matter = Civic::Matter.find_or_initialize_by(
          source_system: Ids::SOURCE_SYSTEM,
          source_matter_id: Ids.matter_source_id(school_id:, mid:, agenda_id:)
        )
        matter.assign_attributes(
          matter_file: Ids.matter_file(mid:, agenda_id:),
          title: item_title,
          body_name: Ids::DEFAULT_BODY_NAME,
          last_synced_at: fetched_at,
          raw_source_digest: response_sha256,
          last_source_snapshot_id: snapshot.id
        )
        matter.save!
        matter
      end
      private_class_method :upsert_matter

      def self.upsert_attachment(matter:, school_id:, mid:, doc:, fetched_at:, response_sha256:, snapshot:)
        attachment = Civic::MatterAttachment.find_or_initialize_by(
          source_system: Ids::SOURCE_SYSTEM,
          source_attachment_id: Ids.attachment_source_id(school_id:, mid:, attachment_id: doc.attachment_id)
        )
        attachment.assign_attributes(
          civic_matter_id: matter.id,
          name: doc.title.presence || doc.file_name,
          file_name: doc.file_name,
          hyperlink: Ids.attachment_url(school_id:, mid:, attachment_id: doc.attachment_id),
          is_supporting_document: true,
          is_hyperlink: false,
          sort_order: doc.order,
          source_present: true,
          source_missing_at: nil,
          last_synced_at: fetched_at,
          raw_source_digest: response_sha256,
          last_source_snapshot_id: snapshot.id
        )
        attachment.save!
        attachment
      end
      private_class_method :upsert_attachment
    end
  end
end
