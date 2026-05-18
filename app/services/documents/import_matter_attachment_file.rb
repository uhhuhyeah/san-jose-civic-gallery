require "tempfile"

module Documents
  class ImportMatterAttachmentFile
    CONTENT_TYPE_EXTENSIONS = {
      "application/pdf" => ".pdf",
      "text/html" => ".html",
      "text/plain" => ".txt",
      "image/jpeg" => ".jpg",
      "image/png" => ".png",
      "application/msword" => ".doc",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => ".docx"
    }.freeze

    def self.call(matter_attachment:, downloader: SafeDownloader)
      raise ArgumentError, "Matter attachment hyperlink is missing" if matter_attachment.hyperlink.blank?

      tempfile = Tempfile.new([ "matter-attachment-#{matter_attachment.legistar_matter_attachment_id}", ".bin" ])
      tempfile.binmode

      begin
        result = downloader.call(url: matter_attachment.hyperlink, io: tempfile)
        tempfile.rewind

        filename = filename_for(matter_attachment, result.content_type)
        content_type = normalized_content_type(result.content_type)

        matter_attachment.source_file.attach(
          io: tempfile,
          filename: filename,
          content_type: content_type
        )

        matter_attachment.update!(
          source_file_imported_at: Time.current,
          source_file_checksum_sha256: result.checksum_sha256,
          source_file_byte_size: result.byte_size,
          source_file_final_url: result.final_url,
          source_file_etag: result.etag,
          source_file_last_modified_at: result.last_modified_at,
          source_file_validated_at: Time.current,
          source_file_validation_error: nil,
          source_file_import_error: nil
        )

        matter_attachment
      rescue StandardError => error
        matter_attachment.update!(
          source_file_import_error: "#{error.class}: #{error.message}"
        )
        raise
      ensure
        tempfile.close
        tempfile.unlink
      end
    end

    def self.filename_for(matter_attachment, content_type)
      return matter_attachment.file_name if matter_attachment.file_name.present?

      extension = extension_for(content_type)
      "#{matter_attachment.legistar_matter_attachment_id}-attachment#{extension}"
    end
    private_class_method :filename_for

    def self.extension_for(content_type)
      return "" if content_type.blank?

      key = content_type.split(";").first&.strip&.downcase
      CONTENT_TYPE_EXTENSIONS.fetch(key, "")
    end
    private_class_method :extension_for

    def self.normalized_content_type(content_type)
      return nil if content_type.blank?

      content_type.split(";").first&.strip
    end
    private_class_method :normalized_content_type
  end
end
