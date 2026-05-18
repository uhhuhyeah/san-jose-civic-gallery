require "test_helper"

module Ingestion
  class SyncEventsForWindowTest < ActiveSupport::TestCase
    setup do
      @start_date = Date.new(2026, 5, 1)
      @end_date = Date.new(2026, 6, 1)
      clear_enqueued_jobs
    end

    test "syncs paged window and marks only missing events inside the bounded window" do
      stale_inside = Civic::Event.create!(
        legistar_event_id: 7000,
        body_name: "City Council",
        event_date: Date.new(2026, 5, 10),
        source_present: true
      )
      outside_window = Civic::Event.create!(
        legistar_event_id: 7001,
        body_name: "City Council",
        event_date: Date.new(2026, 4, 30),
        source_present: true
      )
      other_body = Civic::Event.create!(
        legistar_event_id: 7002,
        body_name: "Planning Commission",
        event_date: Date.new(2026, 5, 10),
        source_present: true
      )
      client = window_client(
        pages: [
          [
            event_payload(7620, "2026-05-05T00:00:00"),
            event_payload(7621, "2026-05-12T00:00:00")
          ],
          [
            event_payload(7622, "2026-05-19T00:00:00")
          ]
        ]
      )

      assert_enqueued_jobs 3, only: Ingestion::SyncEventItemsForEventJob do
        result = SyncEventsForWindow.call(
          body_name: "City Council",
          start_date: @start_date,
          end_date: @end_date,
          client:,
          page_size: 2
        )

        assert_equal [ 7620, 7621, 7622 ], result.events.map(&:legistar_event_id)
        assert_equal [ stale_inside.id ], result.missing_events.map(&:id)
      end

      assert_not stale_inside.reload.source_present
      assert_not_nil stale_inside.source_missing_at
      assert outside_window.reload.source_present
      assert other_body.reload.source_present
      assert_equal [ 0, 2 ], client.skips
    end

    test "normal persistence restores a previously missing event" do
      event = Civic::Event.create!(
        legistar_event_id: 7621,
        body_name: "City Council",
        event_date: Date.new(2026, 5, 12),
        source_present: false,
        source_missing_at: Time.zone.parse("2026-05-15 10:00:00")
      )
      client = window_client(pages: [ [ event_payload(7621, "2026-05-12T00:00:00") ] ])

      SyncEventsForWindow.call(
        body_name: "City Council",
        start_date: @start_date,
        end_date: @end_date,
        client:,
        sync_event_items: false
      )

      assert event.reload.source_present
      assert_nil event.source_missing_at
    end

    test "recent events sync does not mark older local events missing" do
      older_event = Civic::Event.create!(
        legistar_event_id: 7003,
        body_name: "City Council",
        event_date: Date.new(2026, 4, 1),
        source_present: true
      )
      client = Class.new do
        def source_system = "legistar.sanjose"

        def recent_events(limit:, body_name:)
          {
            request_url: "https://example.test/Events?$top=#{limit}",
            status: 200,
            fetched_at: Time.zone.parse("2026-05-17 10:00:00"),
            payload: [
              {
                "EventId" => 7622,
                "EventBodyName" => body_name,
                "EventDate" => "2026-05-19T00:00:00"
              }
            ]
          }
        end
      end.new

      SyncRecentEvents.call(limit: 1, body_name: "City Council", client:, sync_event_items: false)

      assert older_event.reload.source_present
    end

    test "rejects invalid windows" do
      assert_raises(ArgumentError) do
        SyncEventsForWindow.call(
          body_name: "City Council",
          start_date: Date.new(2026, 6, 1),
          end_date: Date.new(2026, 5, 1),
          client: window_client(pages: [])
        )
      end
    end

    private

    def event_payload(event_id, event_date)
      {
        "EventId" => event_id,
        "EventBodyName" => "City Council",
        "EventDate" => event_date,
        "EventAgendaStatusName" => "Final",
        "EventMinutesStatusName" => "Draft"
      }
    end

    def window_client(pages:)
      Class.new do
        attr_reader :skips

        define_method(:initialize) do
          @pages = pages
          @skips = []
        end

        define_method(:source_system) { "legistar.sanjose" }

        define_method(:events_for_window) do |body_name:, start_date:, end_date:, limit:, skip:|
          raise "unexpected body_name" unless body_name == "City Council"
          raise "unexpected start_date" unless start_date == Date.new(2026, 5, 1)
          raise "unexpected end_date" unless end_date == Date.new(2026, 6, 1)
          raise "unexpected limit" unless limit == 2 || limit == Ingestion::SyncEventsForWindow::DEFAULT_PAGE_SIZE

          @skips << skip
          page_index = limit.zero? ? 0 : skip / limit
          {
            request_url: "https://example.test/Events?$skip=#{skip}",
            status: 200,
            fetched_at: Time.zone.parse("2026-05-17 10:00:00"),
            payload: @pages.fetch(page_index, [])
          }
        end
      end.new
    end
  end
end
