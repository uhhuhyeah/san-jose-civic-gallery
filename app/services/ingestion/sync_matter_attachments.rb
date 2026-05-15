module Ingestion
  class SyncMatterAttachments
    Result = Struct.new(:attachments, :snapshots, keyword_init: true)

    def self.call(matter:, client: Legistar::Client.new, import_files: :deferred)
      response = client.matter_attachments(matter_id: matter.legistar_matter_id)

      unless response[:status] == 200
        raise "Legistar MatterAttachments request failed with status #{response[:status]} for #{response[:request_url]}"
      end

      attachments = []
      snapshots = []
      seen_ids = []

      response.fetch(:payload).each do |attachment_payload|
        seen_ids << attachment_payload.fetch("MatterAttachmentId")
        attachment, snapshot = PersistMatterAttachment.call(
          matter:,
          attachment_payload:,
          source_system: client.source_system,
          request_url: response.fetch(:request_url),
          fetched_at: response.fetch(:fetched_at),
          http_status: response.fetch(:status),
          response_sha256: response.fetch(:response_sha256)
        )
        attachments << attachment
        snapshots << snapshot

        fan_out_import(attachment:, mode: import_files) if should_import_attachment?(attachment)
      end

      reconcile_missing_attachments(matter:, seen_ids:, fetched_at: response.fetch(:fetched_at))

      Result.new(attachments:, snapshots:)
    end

    def self.reconcile_missing_attachments(matter:, seen_ids:, fetched_at:)
      missing_scope = Civic::MatterAttachment.where(civic_matter_id: matter.id, source_present: true)
      missing_scope = missing_scope.where.not(legistar_matter_attachment_id: seen_ids) if seen_ids.any?

      missing_scope.update_all(
        source_present: false,
        source_missing_at: fetched_at,
        updated_at: Time.current
      )
    end
    private_class_method :reconcile_missing_attachments

    def self.should_import_attachment?(attachment)
      return false if attachment.hyperlink.blank?
      return true unless attachment.imported?

      attachment.previous_changes.key?("hyperlink") || attachment.previous_changes.key?("file_name")
    end
    private_class_method :should_import_attachment?

    def self.fan_out_import(attachment:, mode:)
      case normalize_mode(mode)
      when :off
        nil
      when :inline
        imported_attachment = Documents::ImportMatterAttachmentFile.call(matter_attachment: attachment)
        Documents::ExtractMatterAttachmentText.call(matter_attachment: imported_attachment) if imported_attachment.extractable_as_pdf?
      when :deferred
        Documents::ImportMatterAttachmentFileJob.perform_later(attachment.id)
      end
    end
    private_class_method :fan_out_import

    def self.normalize_mode(mode)
      return :inline if mode == true
      return :off if mode == false

      mode
    end
    private_class_method :normalize_mode
  end
end
