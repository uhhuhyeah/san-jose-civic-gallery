module Documents
  class ExtractMatterAttachmentText
    def self.call(matter_attachment:, embedded_extractor: ExtractPdfText, ocr_extractor: OcrPdfText)
      active_extractor_name = "pdftotext"
      embedded_result = embedded_extractor.call(matter_attachment:)
      embedded_record = PersistExtractedText.call(matter_attachment:, extraction_result: embedded_result)
      return embedded_record if embedded_result.text.present?

      active_extractor_name = "ocrmypdf"
      ocr_result = ocr_extractor.call(matter_attachment:)
      PersistExtractedText.call(matter_attachment:, extraction_result: ocr_result)
    rescue StandardError => error
      record_failure(matter_attachment:, error:, extractor_name: active_extractor_name)
      raise error
    end

    def self.record_failure(matter_attachment:, error:, extractor_name:)
      Documents::ExtractedText.create!(
        civic_matter_attachment_id: matter_attachment.id,
        extractor_name:,
        extracted_at: Time.current,
        status: "error",
        source_file_checksum_sha256: matter_attachment.source_file_checksum_sha256,
        error_message: "#{error.class}: #{error.message}"
      )
    rescue StandardError => bookkeeping_error
      Rails.logger.error(
        "Documents::ExtractMatterAttachmentText failed to record extraction error for " \
        "matter_attachment=#{matter_attachment.id}: " \
        "#{bookkeeping_error.class}: #{bookkeeping_error.message}"
      )
    end
    private_class_method :record_failure
  end
end
