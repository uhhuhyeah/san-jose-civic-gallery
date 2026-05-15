module Documents
  class PersistExtractedText
    def self.call(matter_attachment:, extraction_result:)
      record = ExtractedText.find_or_initialize_by(civic_matter_attachment_id: matter_attachment.id)
      record.assign_attributes(
        extractor_name: "pdftotext",
        extractor_version: extraction_result.command_version,
        content: extraction_result.text,
        extracted_at: Time.current,
        character_count: extraction_result.text.length,
        status: extraction_result.text.present? ? "ok" : "empty"
      )
      record.save!
      record
    end
  end
end
