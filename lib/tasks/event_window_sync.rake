namespace :ingestion do
  desc "Sync and reconcile events for an explicit body/date window"
  task sync_events_window: :environment do
    body_name = ENV.fetch("BODY_NAME", "City Council")
    start_date = ENV.fetch("START_DATE")
    end_date = ENV.fetch("END_DATE")
    page_size = ENV.fetch("PAGE_SIZE", Ingestion::SyncEventsForWindow::DEFAULT_PAGE_SIZE)
    sync_event_items = ENV.fetch("SYNC_EVENT_ITEMS", "deferred").to_sym

    result = Ingestion::SyncEventsForWindow.call(
      body_name:,
      start_date:,
      end_date:,
      page_size:,
      sync_event_items:
    )

    puts "Synced #{result.events.size} events for #{body_name} from #{start_date} to #{end_date}"
    puts "Marked #{result.missing_events.size} events missing"
    result.missing_events.each do |event|
      puts "- #{event.legistar_event_id} #{event.event_date} #{event.display_name}"
    end
  end
end
