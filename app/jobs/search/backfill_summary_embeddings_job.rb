module Search
  class BackfillSummaryEmbeddingsJob < ApplicationJob
    queue_as :generated_summary

    def perform(limit: BackfillSummaryEmbeddings::DEFAULT_LIMIT, dry_run: false, force: false)
      result = BackfillSummaryEmbeddings.call(limit:, dry_run:, force:)
      Rails.logger.info(
        "Search::BackfillSummaryEmbeddingsJob processed #{result.candidates.count} candidates " \
        "(embedded=#{result.embedded}, skipped=#{result.skipped}, failed=#{result.failed}, dry_run=#{result.dry_run})"
      )
      result
    end
  end
end
