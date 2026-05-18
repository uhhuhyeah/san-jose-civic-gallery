module Ingestion
  class SyncEventsForWindow
    Result = Struct.new(:events, :snapshots, :missing_events, keyword_init: true)

    DEFAULT_PAGE_SIZE = 100
    DEFAULT_BODY_NAME = "City Council"
    MAX_PAGES = 200

    def self.call(
      body_name: DEFAULT_BODY_NAME,
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
      @start_date = coerce_date(:start_date, start_date)
      @end_date = coerce_date(:end_date, end_date)
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
      skip = 0
      pages_fetched = 0

      loop do
        pages_fetched += 1
        if pages_fetched > MAX_PAGES
          raise "Legistar Events window pagination exceeded MAX_PAGES=#{MAX_PAGES} " \
                "for #{@body_name} #{@start_date}..#{@end_date}; the server may be " \
                "ignoring $skip"
        end

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

      missing_events = reconcile_missing_events(seen_ids:)
      Result.new(events:, snapshots:, missing_events:)
    end

    private

    def coerce_date(name, value)
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue ArgumentError, Date::Error
      raise ArgumentError, "#{name} must be a YYYY-MM-DD date (got #{value.inspect})"
    end

    def fan_out_event_items(event:)
      FanOut.dispatch(
        mode: @sync_event_items,
        inline: -> { SyncEventItemsForEvent.call(event:, client: @client, sync_matters: :inline) },
        deferred: -> { SyncEventItemsForEventJob.perform_later(event.id, source_system: @client.source_system) }
      )
    end

    def reconcile_missing_events(seen_ids:)
      missing_scope = Civic::Event
        .where(
          source_system: @client.source_system,
          body_name: @body_name,
          source_present: true,
          event_date: @start_date...@end_date
        )
      missing_scope = missing_scope.where.not(legistar_event_id: seen_ids) if seen_ids.any?

      # Capture the ids first so we can return the post-update rows after
      # the update_all and not hand callers a stale source_present: true
      # snapshot.
      missing_ids = missing_scope.pluck(:id)

      # Use Time.current at reconciliation rather than the first page's
      # fetched_at. For a long pagination, the first-page timestamp
      # understates how recently the missing-marking actually happened.
      now = Time.current
      missing_scope.update_all(
        source_present: false,
        source_missing_at: now,
        updated_at: now
      )

      Civic::Event.where(id: missing_ids).to_a
    end
  end
end
