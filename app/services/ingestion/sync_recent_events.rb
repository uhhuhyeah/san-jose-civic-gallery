module Ingestion
  class SyncRecentEvents
    Result = Struct.new(:events, :snapshots, keyword_init: true)

    def self.call(limit: 10, body_name: "City Council", client: Legistar::Client.new, sync_event_items: :deferred)
      response = client.recent_events(limit:, body_name:)

      unless response[:status] == 200
        raise "Legistar request failed with status #{response[:status]} for #{response[:request_url]}"
      end

      events = []
      snapshots = []

      response.fetch(:payload).each do |event_payload|
        event, snapshot = PersistEvent.call(
          event_payload:,
          source_system: client.source_system,
          request_url: response.fetch(:request_url),
          fetched_at: response.fetch(:fetched_at),
          http_status: response.fetch(:status),
          response_sha256: PayloadDigest.sha256(event_payload)
        )
        events << event
        snapshots << snapshot

        FanOut.dispatch(
          mode: sync_event_items,
          inline: -> { SyncEventItemsForEvent.call(event:, client:, sync_matters: :inline) },
          deferred: -> { SyncEventItemsForEventJob.perform_later(event.id, source_system: client.source_system) }
        )
      end

      Result.new(events:, snapshots:)
    end
  end
end
