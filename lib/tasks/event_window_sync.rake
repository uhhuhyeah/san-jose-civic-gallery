namespace :ingestion do
  ALLOWED_SYNC_EVENT_ITEMS_MODES = %w[deferred inline off].freeze

  desc "Sync and reconcile events for an explicit body/date window. " \
    "Required: START_DATE, END_DATE (YYYY-MM-DD). " \
    "Optional: BODY_NAME (default: City Council), PAGE_SIZE, " \
    "SYNC_EVENT_ITEMS (#{ALLOWED_SYNC_EVENT_ITEMS_MODES.join('|')})."
  task sync_events_window: :environment do
    start_date = ENV.fetch("START_DATE")
    end_date = ENV.fetch("END_DATE")

    sync_event_items_raw = ENV.fetch("SYNC_EVENT_ITEMS", "deferred")
    unless ALLOWED_SYNC_EVENT_ITEMS_MODES.include?(sync_event_items_raw)
      abort "SYNC_EVENT_ITEMS must be one of #{ALLOWED_SYNC_EVENT_ITEMS_MODES.join(', ')} " \
            "(got #{sync_event_items_raw.inspect})"
    end

    call_kwargs = {
      start_date:,
      end_date:,
      page_size: ENV.fetch("PAGE_SIZE", Ingestion::SyncEventsForWindow::DEFAULT_PAGE_SIZE),
      sync_event_items: sync_event_items_raw.to_sym
    }
    call_kwargs[:body_name] = ENV["BODY_NAME"] if ENV["BODY_NAME"].present?

    result = Ingestion::SyncEventsForWindow.call(**call_kwargs)

    effective_body = call_kwargs[:body_name] || Ingestion::SyncEventsForWindow::DEFAULT_BODY_NAME
    puts "Synced #{result.events.size} events for #{effective_body} from #{start_date} to #{end_date}"
    puts "Marked #{result.missing_events.size} events missing"
    result.missing_events.each do |event|
      puts "- #{event.legistar_event_id} #{event.event_date} #{event.display_name}"
    end
  end
end
