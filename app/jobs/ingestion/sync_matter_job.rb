module Ingestion
  class SyncMatterJob < ApplicationJob
    queue_as :default

    def perform(legistar_matter_id)
      result = SyncMatter.call(matter_id: legistar_matter_id)
      Rails.logger.info("Ingestion::SyncMatterJob synced matter #{result.matter.legistar_matter_id}")
      result
    end
  end
end
