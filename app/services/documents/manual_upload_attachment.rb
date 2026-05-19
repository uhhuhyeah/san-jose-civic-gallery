require "digest"
require "marcel"
require "pathname"

module Documents
  # Operator-only path for attaching a PDF to a Civic::MatterAttachment when
  # the source URL is not retrievable by the automated importer (for example,
  # CivicPlus page URLs that sit behind Akamai). Mirrors the metadata
  # bookkeeping ImportMatterAttachmentFile does so the rest of the pipeline
  # (extraction, summary generation, reliability metrics) treats the result
  # the same as an auto-imported file, except for the manual_imported_*
  # columns and the source-of-truth banner the public view renders from them.
  #
  # Use via the bin/rails attachments:manual_upload rake task.
  class ManualUploadAttachment
    class Error < StandardError; end
    class AttachmentNotFound < Error; end
    class PdfNotFound < Error; end
    class NotAPdf < Error; end

    def self.call(attachment_id:, pdf_path:, operator:, reason:)
      new.call(attachment_id:, pdf_path:, operator:, reason:)
    end

    def call(attachment_id:, pdf_path:, operator:, reason:)
      attachment = find_attachment(attachment_id)
      validate_pdf!(pdf_path)

      checksum, byte_size = attach_and_measure(attachment, pdf_path)
      stamp_metadata(attachment, checksum:, byte_size:, operator:, reason:)
      enqueue_extraction(attachment)

      attachment
    end

    private

    def find_attachment(id)
      Civic::MatterAttachment.find_by(id: id) or
        raise AttachmentNotFound, "Civic::MatterAttachment #{id.inspect} not found"
    end

    def validate_pdf!(path)
      raise PdfNotFound, "PDF not found at #{path.inspect}" unless File.exist?(path)

      content_type = Marcel::MimeType.for(Pathname.new(path))
      return if content_type == "application/pdf"

      raise NotAPdf, "Expected application/pdf but #{path.inspect} is #{content_type.inspect}"
    end

    def attach_and_measure(attachment, path)
      digest = Digest::SHA256.new
      byte_size = 0
      File.open(path, "rb") do |io|
        while (chunk = io.read(64 * 1024))
          digest.update(chunk)
          byte_size += chunk.bytesize
        end
      end

      File.open(path, "rb") do |io|
        attachment.source_file.attach(
          io: io,
          filename: File.basename(path),
          content_type: "application/pdf"
        )
      end

      [ digest.hexdigest, byte_size ]
    end

    def stamp_metadata(attachment, checksum:, byte_size:, operator:, reason:)
      now = Time.current
      attachment.update!(
        source_file_imported_at: now,
        source_file_checksum_sha256: checksum,
        source_file_byte_size: byte_size,
        source_file_final_url: attachment.hyperlink,
        source_file_etag: nil,
        source_file_last_modified_at: nil,
        source_file_validated_at: now,
        source_file_validation_error: nil,
        source_file_import_error: nil,
        manually_imported_at: now,
        manually_imported_by: operator,
        manual_import_reason: reason
      )
    end

    def enqueue_extraction(attachment)
      ExtractMatterAttachmentTextJob.perform_later(attachment.id)
    end
  end
end
