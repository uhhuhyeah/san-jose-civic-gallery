module Ingestion
  class SyncEventItemsForEvent
    Result = Struct.new(:event_items, :snapshots, keyword_init: true)
    DEFAULT_MATTER_REFRESH_AFTER = 12.hours

    def self.call(event:, client: Legistar::Client.new, sync_matters: :deferred, matter_refresh_after: DEFAULT_MATTER_REFRESH_AFTER)
      source_system = event.source_system
      response = client.event_items(event_id: event.legistar_event_id)
      if response[:status] != 200
        raise Legistar::Client.error_for(response[:status], response[:request_url])
      end

      event_items = []
      snapshots = []
      seen_ids = []
      payload = response.fetch(:payload)
      matter_ids = payload.filter_map { |event_item_payload| event_item_payload["EventItemMatterId"].presence }.uniq
      existing_matters_by_legistar_id = Civic::Matter
        .where(source_system:, legistar_matter_id: matter_ids)
        .index_by(&:legistar_matter_id)

      payload.each do |event_item_payload|
        seen_ids << event_item_payload.fetch("EventItemId")
        matter_id = event_item_payload["EventItemMatterId"]
        matter = existing_matters_by_legistar_id[matter_id] if matter_id.present?

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
      fan_out_matters(
        matter_ids: refreshable_matter_ids(
          matter_ids:,
          existing_matters_by_legistar_id:,
          fetched_at: response.fetch(:fetched_at),
          refresh_after: matter_refresh_after
        ),
        client:,
        source_system:,
        mode: sync_matters
      )

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

    def self.refreshable_matter_ids(matter_ids:, existing_matters_by_legistar_id:, fetched_at:, refresh_after:)
      matter_ids.select do |matter_id|
        matter_refresh_due?(
          matter: existing_matters_by_legistar_id[matter_id],
          fetched_at:,
          refresh_after:
        )
      end
    end
    private_class_method :refreshable_matter_ids

    def self.matter_refresh_due?(matter:, fetched_at:, refresh_after:)
      return true if matter.blank?
      return true if matter.last_synced_at.blank?
      return true if refresh_after.nil?

      matter.last_synced_at < fetched_at - refresh_after
    end
    private_class_method :matter_refresh_due?

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
