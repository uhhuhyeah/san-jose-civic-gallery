module Ingestion
  class SyncEventItemsForEventJob < ApplicationJob
    queue_as :default

    def perform(civic_event_id)
      event = Civic::Event.find(civic_event_id)
      result = SyncEventItemsForEvent.call(event:)
      Rails.logger.info("Ingestion::SyncEventItemsForEventJob synced #{result.event_items.count} items for event #{event.legistar_event_id}")
      result
    end
  end
end
