module Documents
  class BackfillAttachmentRevalidations
    Result = Struct.new(:candidates, :enqueued, :dry_run, keyword_init: true)

    DEFAULT_LIMIT = 100
    DEFAULT_REVALIDATE_AFTER = 30.days

    def self.call(limit: DEFAULT_LIMIT, dry_run: true, revalidate_after: DEFAULT_REVALIDATE_AFTER, retry_errors: false)
      new(limit:, dry_run:, revalidate_after:, retry_errors:).call
    end

    def initialize(limit:, dry_run:, revalidate_after:, retry_errors:)
      @limit = [ limit.to_i, 0 ].max
      @dry_run = dry_run
      @revalidate_after = revalidate_after
      @retry_errors = retry_errors
    end

    def call
      attachments = candidates.to_a
      attachments.each { |attachment| RevalidateMatterAttachmentFileJob.perform_later(attachment.id) } unless @dry_run

      Result.new(
        candidates: attachments,
        enqueued: @dry_run ? 0 : attachments.size,
        dry_run: @dry_run
      )
    end

    private

    def candidates
      scope = Civic::MatterAttachment
        .current_from_source
        .imported
        .includes(:matter)
        .where(source_file_import_error: nil)
        .where.not(hyperlink: nil)
        .where.not(hyperlink: "")
        .order(Arel.sql("source_file_validated_at ASC NULLS FIRST"), :id)
        .limit(@limit)

      scope = scope.where(source_file_validation_error: nil) unless @retry_errors

      return scope if @revalidate_after.nil?

      scope.where(
        "source_file_validated_at IS NULL OR source_file_validated_at < ?",
        Time.current - @revalidate_after
      )
    end
  end
end
