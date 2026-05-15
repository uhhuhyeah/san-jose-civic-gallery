module Ingestion
  class PersistMatterAttachment
    def self.call(matter:, attachment_payload:, source_system:, request_url:, fetched_at:, http_status:, response_sha256:)
      snapshot = RecordSourceSnapshot.call(
        source_system: source_system,
        resource_type: "matter_attachment",
        source_id: attachment_payload.fetch("MatterAttachmentId").to_s,
        request_url: request_url,
        fetched_at: fetched_at,
        http_status: http_status,
        response_sha256: response_sha256,
        payload: attachment_payload
      )

      attachment = Civic::MatterAttachment.find_or_initialize_by(
        source_system: source_system,
        legistar_matter_attachment_id: attachment_payload.fetch("MatterAttachmentId")
      )
      attachment.assign_attributes(attributes_from(matter:, attachment_payload:, fetched_at:, response_sha256:, snapshot:))
      attachment.save!

      [ attachment, snapshot ]
    end

    def self.attributes_from(matter:, attachment_payload:, fetched_at:, response_sha256:, snapshot:)
      {
        civic_matter_id: matter.id,
        name: attachment_payload["MatterAttachmentName"],
        hyperlink: attachment_payload["MatterAttachmentHyperlink"],
        file_name: attachment_payload["MatterAttachmentFileName"],
        matter_version: attachment_payload["MatterAttachmentMatterVersion"],
        is_hyperlink: attachment_payload["MatterAttachmentIsHyperlink"],
        is_supporting_document: attachment_payload["MatterAttachmentIsSupportingDocument"],
        show_on_internet_page: attachment_payload["MatterAttachmentShowOnInternetPage"],
        is_minute_order: attachment_payload["MatterAttachmentIsMinuteOrder"],
        is_board_letter: attachment_payload["MatterAttachmentIsBoardLetter"],
        description: attachment_payload["MatterAttachmentDescription"],
        print_with_reports: attachment_payload["MatterAttachmentPrintWithReports"],
        sort_order: attachment_payload["MatterAttachmentSort"],
        source_present: true,
        source_missing_at: nil,
        source_last_modified_at: attachment_payload["MatterAttachmentLastModifiedUtc"],
        last_synced_at: fetched_at,
        raw_source_digest: response_sha256,
        last_source_snapshot_id: snapshot.id
      }
    end
    private_class_method :attributes_from
  end
end
