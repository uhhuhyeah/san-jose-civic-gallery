module Ingestion
  class SyncEventItemsForEvent
    Result = Struct.new(:event_items, :snapshots, keyword_init: true)

    def self.call(event:, client: Legistar::Client.new, sync_matters: :deferred)
      source_system = event.source_system
      response = client.event_items(event_id: event.legistar_event_id)

      unless response[:status] == 200
        raise "Legistar EventItems request failed with status #{response[:status]} for #{response[:request_url]}"
      end

      event_items = []
      snapshots = []
      matter_ids = []
      seen_ids = []

      response.fetch(:payload).each do |event_item_payload|
        seen_ids << event_item_payload.fetch("EventItemId")
        matter_id = event_item_payload["EventItemMatterId"]
        matter_ids << matter_id if matter_id.present?
        matter = Civic::Matter.find_by(source_system:, legistar_matter_id: matter_id) if matter_id.present?

        event_item, snapshot = PersistEventItem.call(
          event:,
          event_item_payload:,
          source_system:,
          request_url: response.fetch(:request_url),
          fetched_at: response.fetch(:fetched_at),
          http_status: response.fetch(:status),
          response_sha256: PayloadDigest.sha256(event_item_payload),
          matter:
        )
        event_items << event_item
        snapshots << snapshot
      end

      reconcile_missing_items(event:, seen_ids:, fetched_at: response.fetch(:fetched_at))
      fan_out_matters(matter_ids: matter_ids.uniq, client:, source_system:, mode: sync_matters)

      Result.new(event_items:, snapshots:)
    end

    def self.reconcile_missing_items(event:, seen_ids:, fetched_at:)
      missing_scope = Civic::EventItem.where(civic_event_id: event.id, source_present: true)
      missing_scope = missing_scope.where.not(legistar_event_item_id: seen_ids) if seen_ids.any?

      missing_scope.update_all(
        source_present: false,
        source_missing_at: fetched_at,
        updated_at: Time.current
      )
    end
    private_class_method :reconcile_missing_items

    def self.fan_out_matters(matter_ids:, client:, source_system:, mode:)
      matter_ids.each do |matter_id|
        FanOut.dispatch(
          mode: mode,
          inline: -> { SyncMatter.call(matter_id:, client:, sync_attachments: :inline) },
          deferred: -> { SyncMatterJob.perform_later(matter_id, source_system:) }
        )
      end
    end
    private_class_method :fan_out_matters
  end
end
