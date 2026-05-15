module Ingestion
  class SyncEventItemsForEvent
    Result = Struct.new(:event_items, :snapshots, keyword_init: true)

    def self.call(event:, client: Legistar::Client.new, sync_matters: :deferred)
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
        matter = Civic::Matter.find_by(legistar_matter_id: matter_id) if matter_id.present?

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

      reconcile_missing_items(event:, seen_ids:, fetched_at: response.fetch(:fetched_at))
      fan_out_matters(matter_ids: matter_ids.uniq, client:, mode: sync_matters)

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

    def self.fan_out_matters(matter_ids:, client:, mode:)
      case normalize_mode(mode)
      when :off
        nil
      when :inline
        matter_ids.each { |matter_id| SyncMatter.call(matter_id:, client:, sync_attachments: :inline) }
      when :deferred
        matter_ids.each { |matter_id| SyncMatterJob.perform_later(matter_id) }
      end
    end
    private_class_method :fan_out_matters

    def self.normalize_mode(mode)
      return :inline if mode == true
      return :off if mode == false

      mode
    end
    private_class_method :normalize_mode
  end
end
