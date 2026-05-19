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

      # Manually-uploaded attachments substitute for a source URL we cannot
      # actually fetch (e.g. CivicPlus pages behind Akamai). Probing that
      # URL would either fail or return the original blocked response, so
      # we skip revalidation entirely. Operators who want to re-trigger a
      # full check should clear manually_imported_at first.
      if @matter_attachment.manually_imported?
        return Result.new(matter_attachment: @matter_attachment, action: :skipped_manual_import, probe_result: nil)
      end

      # Always probe the canonical hyperlink: any saved source_file_final_url
      # may be a short-lived CDN redirect target that no longer resolves.
      probe_result = @probe.call(
        url: @matter_attachment.hyperlink,
        etag: @matter_attachment.source_file_etag,
        last_modified_at: @matter_attachment.source_file_last_modified_at
      )

      if probe_result.not_modified? || unchanged?(probe_result)
        mark_validated!(probe_result)
        Result.new(matter_attachment: @matter_attachment, action: :unchanged, probe_result:)
      else
        reimport!
        Result.new(matter_attachment: @matter_attachment, action: :reimported, probe_result:)
      end
    rescue StandardError => error
      record_validation_error(error)
      raise
    end

    private

    def reimport!
      was_extractable = @matter_attachment.extractable_as_pdf?
      @importer.call(matter_attachment: @matter_attachment)
      @matter_attachment.reload

      # Prior extracted_text rows describe the previous file contents.
      # Supersede them so search stops returning stale content while the
      # next extraction runs (or permanently, if the new file is no
      # longer extractable as a PDF).
      supersede_prior_extractions!

      if @matter_attachment.extractable_as_pdf?
        ExtractMatterAttachmentTextJob.perform_later(@matter_attachment.id)
      elsif was_extractable
        Rails.logger.warn(
          "Documents::RevalidateMatterAttachmentFile reimported " \
          "matter_attachment=#{@matter_attachment.id} as a non-PDF; " \
          "prior extracted text marked superseded and no extraction enqueued"
        )
      end
    end

    def supersede_prior_extractions!
      @matter_attachment.extracted_texts
        .where(status: [ "ok", "empty" ])
        .update_all(status: "superseded", updated_at: Time.current)
    end

    def unchanged?(result)
      # ETag is the most reliable validator. Prefer it when both sides have one.
      return matches_etag?(result) if etag_available?(result)

      # Fall back to Last-Modified when both sides report it.
      return matches_last_modified?(result) if last_modified_available?(result)

      # Fall back to Content-Length when both sides report it.
      return matches_byte_size?(result) if byte_size_available?(result)

      # Server gave us no validators we can compare against. Treat as
      # unchanged so revalidation stays a cheap HEAD instead of a full
      # re-download on every cycle. Operators can force a reimport by
      # clearing source_file_validated_at.
      Rails.logger.info(
        "Documents::RevalidateMatterAttachmentFile no comparable validators for " \
        "matter_attachment=#{@matter_attachment.id}; treating as unchanged"
      )
      true
    end

    def etag_available?(result)
      @matter_attachment.source_file_etag.present? && result.etag.present?
    end

    def matches_etag?(result)
      @matter_attachment.source_file_etag == result.etag
    end

    def last_modified_available?(result)
      @matter_attachment.source_file_last_modified_at.present? && result.last_modified_at.present?
    end

    def matches_last_modified?(result)
      @matter_attachment.source_file_last_modified_at.to_i == result.last_modified_at.to_i
    end

    def byte_size_available?(result)
      @matter_attachment.source_file_byte_size.present? && result.content_length.present?
    end

    def matches_byte_size?(result)
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

    def record_validation_error(error)
      @matter_attachment.update!(source_file_validation_error: "#{error.class}: #{error.message}")
    rescue StandardError => bookkeeping_error
      Rails.logger.error(
        "Documents::RevalidateMatterAttachmentFile failed to record validation error for " \
        "matter_attachment=#{@matter_attachment.id}: " \
        "#{bookkeeping_error.class}: #{bookkeeping_error.message}"
      )
    end
  end
end
