module Generated
  class BackfillMatterThemesJob < ApplicationJob
    queue_as :generated_summary

    def perform(limit: BackfillMatterThemes::DEFAULT_LIMIT, dry_run: false, force: false)
      result = BackfillMatterThemes.call(limit:, dry_run:, force:)
      Rails.logger.info(
        "Generated::BackfillMatterThemesJob processed #{result.candidates.count} candidates " \
        "(generated=#{result.generated}, skipped=#{result.skipped}, failed=#{result.failed}, dry_run=#{result.dry_run})"
      )
      result
    end
  end
end
