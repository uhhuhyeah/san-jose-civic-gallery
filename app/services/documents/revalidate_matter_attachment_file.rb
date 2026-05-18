module Documents
  class RevalidateMatterAttachmentFile
    Result = Struct.new(:matter_attachment, :action, :probe_result, keyword_init: true)

    def self.call(matter_attachment:, probe: RemoteFileProbe, importer: ImportMatterAttachmentFile)
      new(matter_attachment:, probe:, importer:).call
    end

    def initialize(matter_attachment:, probe:, importer:)
      @matter_attachment = matter_attachment
      @probe = probe
      @importer = importer
    end

    def call
      raise ArgumentError, "Matter attachment source file is not attached" unless @matter_attachment.source_file.attached?
      raise ArgumentError, "Matter attachment hyperlink is missing" if @matter_attachment.hyperlink.blank?

      result = @probe.call(
        url: @matter_attachment.source_file_final_url.presence || @matter_attachment.hyperlink,
        etag: @matter_attachment.source_file_etag,
        last_modified_at: @matter_attachment.source_file_last_modified_at
      )

      if result.not_modified? || unchanged?(result)
        mark_validated!(result)
        return Result.new(matter_attachment: @matter_attachment, action: :unchanged, probe_result: result)
      end

      @importer.call(matter_attachment: @matter_attachment)
      ExtractMatterAttachmentTextJob.perform_later(@matter_attachment.id) if @matter_attachment.reload.extractable_as_pdf?
      Result.new(matter_attachment: @matter_attachment.reload, action: :reimported, probe_result: result)
    rescue StandardError => error
      @matter_attachment.update!(source_file_validation_error: "#{error.class}: #{error.message}")
      raise
    end

    private

    def unchanged?(result)
      return @matter_attachment.source_file_etag == result.etag if comparable_etag?(result)
      return @matter_attachment.source_file_last_modified_at.to_i == result.last_modified_at.to_i if comparable_last_modified?(result)
      return @matter_attachment.source_file_byte_size == result.content_length if comparable_byte_size?(result)

      false
    end

    def comparable_etag?(result)
      @matter_attachment.source_file_etag.present? &&
        result.etag.present?
    end

    def comparable_last_modified?(result)
      @matter_attachment.source_file_last_modified_at.present? &&
        result.last_modified_at.present?
    end

    def comparable_byte_size?(result)
      @matter_attachment.source_file_byte_size.present? &&
        result.content_length.present? &&
        @matter_attachment.source_file_byte_size == result.content_length
    end

    def mark_validated!(result)
      @matter_attachment.update!(
        source_file_final_url: result.final_url.presence || @matter_attachment.source_file_final_url,
        source_file_etag: result.etag.presence || @matter_attachment.source_file_etag,
        source_file_last_modified_at: result.last_modified_at || @matter_attachment.source_file_last_modified_at,
        source_file_validated_at: Time.current,
        source_file_validation_error: nil
      )
    end
  end
end
