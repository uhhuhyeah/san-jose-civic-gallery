module Ingestion
  class SyncMatterAttachmentsJob < ApplicationJob
    queue_as :default

    def perform(civic_matter_id)
      matter = Civic::Matter.find(civic_matter_id)
      result = SyncMatterAttachments.call(matter:)
      Rails.logger.info("Ingestion::SyncMatterAttachmentsJob synced #{result.attachments.count} attachments for matter #{matter.legistar_matter_id}")
      result
    end
  end
end
