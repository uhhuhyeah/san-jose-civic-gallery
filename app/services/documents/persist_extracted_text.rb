module Documents
  class PersistExtractedText
    def self.call(matter_attachment:, extraction_result:)
      ExtractedText.create!(
        civic_matter_attachment_id: matter_attachment.id,
        extractor_name: extraction_result.extractor_name,
        extractor_version: extraction_result.command_version,
        content: extraction_result.text,
        extracted_at: Time.current,
        character_count: extraction_result.text.length,
        source_file_checksum_sha256: matter_attachment.source_file_checksum_sha256,
        status: extraction_result.text.present? ? "ok" : "empty"
      )
    end
  end
end
