module Ingestion
  class SyncEventItemsForEventJob < ApplicationJob
    queue_as :default

    def perform(civic_event_id, source_system: nil)
      event = Civic::Event.find(civic_event_id)
      client = Legistar::Client.new(source_system: source_system || event.source_system)
      result = SyncEventItemsForEvent.call(event:, client:)
      Rails.logger.info("Ingestion::SyncEventItemsForEventJob synced #{result.event_items.count} items for event #{event.legistar_event_id}")
      result
    end
  end
end
