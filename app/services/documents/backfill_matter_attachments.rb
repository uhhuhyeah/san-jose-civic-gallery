module Documents
  class BackfillMatterAttachments
    Result = Struct.new(
      :import_candidates,
      :extraction_candidates,
      :import_enqueued,
      :extraction_enqueued,
      :dry_run,
      keyword_init: true
    )

    DEFAULT_LIMIT = 100

    def self.call(limit: DEFAULT_LIMIT, dry_run: true, matter_file: nil, from_date: nil, to_date: nil, retry_errors: false)
      new(
        limit:,
        dry_run:,
        matter_file:,
        from_date:,
        to_date:,
        retry_errors:
      ).call
    end

    def initialize(limit:, dry_run:, matter_file:, from_date:, to_date:, retry_errors:)
      @limit = [ limit.to_i, 0 ].max
      @dry_run = dry_run
      @matter_file = matter_file.presence
      @from_date = coerce_date(:from_date, from_date)
      @to_date = coerce_date(:to_date, to_date)
      @retry_errors = retry_errors
    end

    def call
      imports = import_candidates.to_a
      remaining_limit = [ @limit - imports.size, 0 ].max
      extractions = remaining_limit.zero? ? [] : extraction_candidates.limit(remaining_limit).to_a

      unless @dry_run
        imports.each { |attachment| ImportMatterAttachmentFileJob.perform_later(attachment.id) }
        extractions.each { |attachment| ExtractMatterAttachmentTextJob.perform_later(attachment.id) }
      end

      Result.new(
        import_candidates: imports,
        extraction_candidates: extractions,
        import_enqueued: @dry_run ? 0 : imports.size,
        extraction_enqueued: @dry_run ? 0 : extractions.size,
        dry_run: @dry_run
      )
    end

    private

    def import_candidates
      scope = base_scope
        .left_joins(:source_file_attachment)
        .where(active_storage_attachments: { id: nil })
        .where.not(hyperlink: nil)
        .where.not(hyperlink: "")

      scope = scope.where(source_file_import_error: nil) unless @retry_errors

      scope.display_order.limit(@limit)
    end

    def extraction_candidates
      # Exclude attachments that already have a successful extracted_text row.
      attachments_with_successful_text = Documents::ExtractedText.successful.select(:civic_matter_attachment_id)

      base_scope
        .joins(source_file_attachment: :blob)
        .where.not(id: attachments_with_successful_text)
        .where(
          "active_storage_blobs.content_type = :pdf_type OR lower(active_storage_blobs.filename) LIKE :pdf_extension",
          pdf_type: "application/pdf",
          pdf_extension: "%.pdf"
        )
        .includes(source_file_attachment: :blob)
        .display_order
    end

    def base_scope
      scope = Civic::MatterAttachment.current_from_source.joins(:matter).includes(:matter)
      scope = scope.where(civic_matters: { matter_file: @matter_file }) if @matter_file
      scope = scope.where("civic_matters.agenda_date >= ?", @from_date) if @from_date
      scope = scope.where("civic_matters.agenda_date <= ?", @to_date) if @to_date
      scope
    end

    def coerce_date(name, value)
      return if value.blank?
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue ArgumentError, Date::Error
      raise ArgumentError, "#{name} must be a YYYY-MM-DD date (got #{value.inspect})"
    end
  end
end
