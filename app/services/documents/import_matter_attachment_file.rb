require "digest"
require "open-uri"
require "stringio"

module Documents
  class ImportMatterAttachmentFile
    def self.call(matter_attachment:)
      raise ArgumentError, "Matter attachment hyperlink is missing" if matter_attachment.hyperlink.blank?

      io = URI.open(matter_attachment.hyperlink, "rb")
      data = io.read
      checksum = Digest::SHA256.hexdigest(data)

      matter_attachment.source_file.attach(
        io: StringIO.new(data),
        filename: matter_attachment.file_name.presence || inferred_filename(matter_attachment),
        content_type: Marcel::MimeType.for(StringIO.new(data), name: matter_attachment.file_name)
      )

      matter_attachment.update!(
        source_file_imported_at: Time.current,
        source_file_checksum_sha256: checksum,
        source_file_byte_size: data.bytesize,
        source_file_import_error: nil
      )

      matter_attachment
    rescue StandardError => error
      matter_attachment.update!(
        source_file_import_error: "#{error.class}: #{error.message}"
      )
      raise
    end

    def self.inferred_filename(matter_attachment)
      "#{matter_attachment.legistar_matter_attachment_id}-attachment"
    end
    private_class_method :inferred_filename
  end
end
