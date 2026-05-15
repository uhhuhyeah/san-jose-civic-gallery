module Documents
  class ExtractMatterAttachmentText
    def self.call(matter_attachment:)
      extraction_result = ExtractPdfText.call(matter_attachment:)
      PersistExtractedText.call(matter_attachment:, extraction_result:)
    rescue StandardError => error
      record = Documents::ExtractedText.find_or_initialize_by(civic_matter_attachment_id: matter_attachment.id)
      record.assign_attributes(
        extractor_name: "pdftotext",
        extracted_at: Time.current,
        status: "error",
        error_message: "#{error.class}: #{error.message}"
      )
      record.save!
      raise
    end
  end
end
