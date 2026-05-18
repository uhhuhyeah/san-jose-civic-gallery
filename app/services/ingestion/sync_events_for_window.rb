module Ingestion
  class SyncEventsForWindow
    Result = Struct.new(:events, :snapshots, :missing_events, keyword_init: true)

    DEFAULT_PAGE_SIZE = 100

    def self.call(
      body_name: "City Council",
      start_date:,
      end_date:,
      client: Legistar::Client.new,
      sync_event_items: :deferred,
      page_size: DEFAULT_PAGE_SIZE
    )
      new(
        body_name:,
        start_date:,
        end_date:,
        client:,
        sync_event_items:,
        page_size:
      ).call
    end

    def initialize(body_name:, start_date:, end_date:, client:, sync_event_items:, page_size:)
      @body_name = body_name
      @start_date = coerce_date(start_date)
      @end_date = coerce_date(end_date)
      @client = client
      @sync_event_items = sync_event_items
      @page_size = page_size.to_i
      raise ArgumentError, "end_date must be after start_date" unless @end_date > @start_date
      raise ArgumentError, "page_size must be positive" unless @page_size.positive?
    end

    def call
      events = []
      snapshots = []
      seen_ids = []
      fetched_at = nil
      skip = 0

      loop do
        response = @client.events_for_window(
          body_name: @body_name,
          start_date: @start_date,
          end_date: @end_date,
          limit: @page_size,
          skip:
        )
        unless response[:status] == 200
          raise "Legistar Events window request failed with status #{response[:status]} for #{response[:request_url]}"
        end

        fetched_at ||= response.fetch(:fetched_at)
        payload = response.fetch(:payload)
        payload.each do |event_payload|
          seen_ids << event_payload.fetch("EventId")
          event, snapshot = PersistEvent.call(
            event_payload:,
            source_system: @client.source_system,
            request_url: response.fetch(:request_url),
            fetched_at: response.fetch(:fetched_at),
            http_status: response.fetch(:status),
            response_sha256: PayloadDigest.sha256(event_payload)
          )
          events << event
          snapshots << snapshot

          fan_out_event_items(event:)
        end

        break if payload.size < @page_size

        skip += @page_size
      end

      missing_events = reconcile_missing_events(seen_ids:, fetched_at: fetched_at || Time.current)
      Result.new(events:, snapshots:, missing_events:)
    end

    private

    def coerce_date(value)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    end

    def fan_out_event_items(event:)
      FanOut.dispatch(
        mode: @sync_event_items,
        inline: -> { SyncEventItemsForEvent.call(event:, client: @client, sync_matters: :inline) },
        deferred: -> { SyncEventItemsForEventJob.perform_later(event.id, source_system: @client.source_system) }
      )
    end

    def reconcile_missing_events(seen_ids:, fetched_at:)
      missing_scope = Civic::Event
        .where(
          source_system: @client.source_system,
          body_name: @body_name,
          source_present: true,
          event_date: @start_date...@end_date
        )
      missing_scope = missing_scope.where.not(legistar_event_id: seen_ids) if seen_ids.any?

      missing_events = missing_scope.to_a
      missing_scope.update_all(
        source_present: false,
        source_missing_at: fetched_at,
        updated_at: Time.current
      )
      missing_events
    end
  end
end
