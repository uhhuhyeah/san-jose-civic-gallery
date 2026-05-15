module Ingestion
  class SyncRecentEventsJob < ApplicationJob
    queue_as :default

    def perform(limit: 10, body_name: "City Council", source_system: nil)
      result = SyncRecentEvents.call(
        limit:,
        body_name:,
        client: Legistar::Client.new(source_system:)
      )
      Rails.logger.info("Ingestion::SyncRecentEventsJob synced #{result.events.count} events for #{body_name}")
      result
    end
  end
end
