require "test_helper"

module Ingestion
  class SyncEventItemsForEventTest < ActiveSupport::TestCase
    setup do
      @event = Civic::Event.create!(
        legistar_event_id: 7622,
        body_name: "City Council",
        event_date: Date.new(2026, 5, 19)
      )
      @stale_item = @event.all_event_items.create!(
        legistar_event_item_id: 999,
        title: "Removed item"
      )
      clear_enqueued_jobs
    end

    test "reconciles missing items and fans out unique matter sync jobs" do
      payload = [
        {
          "EventItemId" => 129630,
          "EventItemAgendaSequence" => 1,
          "EventItemTitle" => "First item",
          "EventItemMatterId" => 15886,
          "EventItemLastModifiedUtc" => "2026-05-15T12:00:00Z"
        },
        {
          "EventItemId" => 129631,
          "EventItemAgendaSequence" => 2,
          "EventItemTitle" => "Second item",
          "EventItemMatterId" => 15886,
          "EventItemLastModifiedUtc" => "2026-05-15T12:01:00Z"
        }
      ]

      client = Class.new do
        define_method(:source_system) { "legistar.sanjose" }

        define_method(:event_items) do |event_id:|
          raise "unexpected event_id" unless event_id == 7622

          {
            request_url: "https://example.test/Events/7622/EventItems",
            status: 200,
            fetched_at: Time.zone.parse("2026-05-15 09:00:00"),
            response_sha256: "event-items-sha",
            payload:
          }
        end

        define_method(:payload) { payload }
      end.new

      assert_enqueued_jobs 1, only: Ingestion::SyncMatterJob do
        SyncEventItemsForEvent.call(event: @event, client:, sync_matters: :deferred)
      end

      @stale_item.reload
      assert_not @stale_item.source_present
      assert_equal Time.zone.parse("2026-05-15 09:00:00"), @stale_item.source_missing_at

      current_ids = @event.event_items.pluck(:legistar_event_item_id)
      assert_equal [ 129630, 129631 ], current_ids

      enqueued_matter_ids = enqueued_jobs.to_a.filter_map do |job|
        next unless job.fetch("job_class") == "Ingestion::SyncMatterJob"

        job.fetch("arguments").first
      end

      assert_equal [ 15886 ], enqueued_matter_ids
    end
  end
end
