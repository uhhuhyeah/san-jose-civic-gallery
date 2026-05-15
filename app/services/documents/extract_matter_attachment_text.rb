module Documents
  class ExtractMatterAttachmentText
    def self.call(matter_attachment:)
      extraction_result = ExtractPdfText.call(matter_attachment:)
      PersistExtractedText.call(matter_attachment:, extraction_result:)
    rescue StandardError => error
      Documents::ExtractedText.create!(
        civic_matter_attachment_id: matter_attachment.id,
        extractor_name: "pdftotext",
        extracted_at: Time.current,
        status: "error",
        source_file_checksum_sha256: matter_attachment.source_file_checksum_sha256,
        error_message: "#{error.class}: #{error.message}"
      )
      raise
    end
  end
end
