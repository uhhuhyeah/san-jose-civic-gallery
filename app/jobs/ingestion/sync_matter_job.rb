module Ingestion
  class SyncMatterJob < ApplicationJob
    queue_as :default

    def perform(legistar_matter_id, source_system: Legistar::Client::DEFAULT_SOURCE_SYSTEM)
      result = SyncMatter.call(
        matter_id: legistar_matter_id,
        client: Legistar::Client.new(source_system:)
      )
      Rails.logger.info("Ingestion::SyncMatterJob synced matter #{result.matter.legistar_matter_id}")
      result
    end
  end
end
