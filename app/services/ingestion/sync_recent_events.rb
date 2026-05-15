module Ingestion
  class SyncRecentEvents
    Result = Struct.new(:events, :snapshots, keyword_init: true)

    def self.call(limit: 10, body_name: "City Council", client: Legistar::Client.new, sync_event_items: true)
      response = client.recent_events(limit:, body_name:)

      unless response[:status] == 200
        raise "Legistar request failed with status #{response[:status]} for #{response[:request_url]}"
      end

      events = []
      snapshots = []

      response.fetch(:payload).each do |event_payload|
        event, snapshot = PersistEvent.call(
          event_payload:,
          request_url: response.fetch(:request_url),
          fetched_at: response.fetch(:fetched_at),
          http_status: response.fetch(:status),
          response_sha256: response.fetch(:response_sha256)
        )
        events << event
        snapshots << snapshot

        SyncEventItemsForEvent.call(event:, client:) if sync_event_items
      end

      Result.new(events:, snapshots:)
    end
  end
end
