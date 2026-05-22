module Generated
  class BackfillEventSummariesJob < ApplicationJob
    queue_as :generated_summary

    def perform(limit: BackfillEventSummaries::DEFAULT_LIMIT, dry_run: false, force: false)
      result = BackfillEventSummaries.call(limit:, dry_run:, force:)
      Rails.logger.info(
        "Generated::BackfillEventSummariesJob processed #{result.candidates.count} candidates " \
        "(generated=#{result.generated}, skipped=#{result.skipped}, failed=#{result.failed}, dry_run=#{result.dry_run})"
      )
      result
    end
  end
end
