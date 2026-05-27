require "tempfile"

module Documents
  # Last-resort recovery for an attachment whose source download is blocked
  # (for example, an Akamai HTTP 403). Many Civic::MatterAttachment rows point
  # at the same source hyperlink: when an operator has already manually
  # uploaded the file for one of those rows, copy that file across to the
  # blocked row and stamp it as a manual upload too, rather than asking an
  # operator to re-upload a document the system already holds.
  #
  # Only invoked after an access-blocked HTTP response (see
  # ImportMatterAttachmentFile), where treating same-URL-as-same-content is an
  # accepted assumption. Returns the recovered attachment, or nil when no
  # reusable sibling exists.
  class ReuseManualSiblingFile
    def self.call(matter_attachment:)
      new.call(matter_attachment:)
    end

    def call(matter_attachment:)
      sibling = manual_sibling_for(matter_attachment)
      return nil unless sibling

      # Upload the duplicated blob before opening the transaction: attaching an
      # io inside a transaction defers the upload to commit (after the source
      # tempfile is closed). With a fully-uploaded blob in hand, the
      # transaction only associates it and stamps provenance, so a failed stamp
      # rolls back the attachment row rather than leaving a file attached with
      # blank manually_imported_* columns. (A rollback orphans the stored blob
      # but keeps the record coherent.)
      blob = duplicate_blob(sibling.source_file)

      matter_attachment.transaction do
        matter_attachment.source_file.attach(blob)
        stamp_metadata(matter_attachment, sibling)
      end

      matter_attachment
    end

    private

    def manual_sibling_for(attachment)
      return nil if attachment.hyperlink.blank?

      Civic::MatterAttachment
        .where(hyperlink: attachment.hyperlink)
        .where.not(id: attachment.id)
        .where.not(manually_imported_at: nil)
        .where.associated(:source_file_attachment)
        .order(manually_imported_at: :desc)
        .first
    end

    # Stream the sibling's bytes into a new, independently stored blob so the
    # recovered row does not share a blob with its sibling (purging one would
    # otherwise orphan the other).
    def duplicate_blob(source_file)
      tempfile = Tempfile.new([ "reuse-sibling-attachment", File.extname(source_file.filename.to_s) ])
      tempfile.binmode
      source_file.download { |chunk| tempfile.write(chunk) }
      tempfile.rewind

      ActiveStorage::Blob.create_and_upload!(
        io: tempfile,
        filename: source_file.filename.to_s,
        content_type: source_file.content_type
      )
    ensure
      tempfile&.close
      tempfile&.unlink
    end

    def stamp_metadata(attachment, sibling)
      now = Time.current
      attachment.update!(
        source_file_imported_at: now,
        source_file_checksum_sha256: sibling.source_file_checksum_sha256,
        source_file_byte_size: sibling.source_file_byte_size,
        source_file_final_url: attachment.hyperlink,
        source_file_etag: nil,
        source_file_last_modified_at: nil,
        source_file_validated_at: now,
        source_file_validation_error: nil,
        source_file_import_error: nil,
        manually_imported_at: now,
        manually_imported_by: sibling.manually_imported_by,
        manual_import_reason: reason_for(sibling)
      )
    end

    def reason_for(sibling)
      "Reused operator upload from attachment ##{sibling.id} (same source " \
        "hyperlink) after the source download was blocked"
    end
  end
end
