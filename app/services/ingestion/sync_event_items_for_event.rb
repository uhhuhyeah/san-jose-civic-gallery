module Ingestion
  class SyncEventItemsForEvent
    Result = Struct.new(:event_items, :snapshots, keyword_init: true)

    def self.call(event:, client: Legistar::Client.new)
      response = client.event_items(event_id: event.legistar_event_id)

      unless response[:status] == 200
        raise "Legistar EventItems request failed with status #{response[:status]} for #{response[:request_url]}"
      end

      event_items = []
      snapshots = []

      response.fetch(:payload).each do |event_item_payload|
        matter = nil
        if event_item_payload["EventItemMatterId"].present?
          matter = SyncMatter.call(matter_id: event_item_payload["EventItemMatterId"], client:).matter
        end

        event_item, snapshot = PersistEventItem.call(
          event:,
          event_item_payload:,
          request_url: response.fetch(:request_url),
          fetched_at: response.fetch(:fetched_at),
          http_status: response.fetch(:status),
          response_sha256: response.fetch(:response_sha256),
          matter:
        )
        event_items << event_item
        snapshots << snapshot
      end

      Result.new(event_items:, snapshots:)
    end
  end
end
