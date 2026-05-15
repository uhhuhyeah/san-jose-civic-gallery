require "test_helper"

module Ingestion
  class PersistEventTest < ActiveSupport::TestCase
    test "persists an event and raw snapshot" do
      event_payload = {
        "EventId" => 7621,
        "EventBodyName" => "City Council",
        "EventDate" => "2026-05-12T00:00:00",
        "EventTime" => "13:30",
        "EventTitle" => "Regular meeting",
        "EventAgendaStatusName" => "Agenda",
        "EventMinutesStatusName" => "Draft",
        "EventInSiteURL" => "https://example.test/event/7621",
        "EventLastModifiedUtc" => "2026-05-12T18:30:00Z"
      }

      event, snapshot = PersistEvent.call(
        event_payload:,
        source_system: "legistar.sanjose",
        request_url: "https://example.test/Events",
        fetched_at: Time.zone.parse("2026-05-15 07:00:00"),
        http_status: 200,
        response_sha256: "abc123"
      )

      assert_equal 7621, event.legistar_event_id
      assert_equal "City Council", event.body_name
      assert_equal "Regular meeting", event.title
      assert_equal "legistar.sanjose", event.source_system
      assert_equal snapshot.id, event.last_source_snapshot_id
      assert_equal "legistar.sanjose", snapshot.source_system
      assert_equal "event", snapshot.resource_type
      assert_equal "7621", snapshot.source_id
    end

    test "same legistar_event_id from a different source_system does not collide" do
      payload = lambda do |id|
        {
          "EventId" => id,
          "EventBodyName" => "City Council",
          "EventDate" => "2026-05-12T00:00:00",
          "EventTitle" => "Regular meeting"
        }
      end

      a, _ = PersistEvent.call(
        event_payload: payload.call(7621),
        source_system: "legistar.sanjose",
        request_url: "https://example.test/Events",
        fetched_at: Time.current,
        http_status: 200,
        response_sha256: "sha-a"
      )
      b, _ = PersistEvent.call(
        event_payload: payload.call(7621),
        source_system: "legistar.santaclara",
        request_url: "https://example.test/Events",
        fetched_at: Time.current,
        http_status: 200,
        response_sha256: "sha-b"
      )

      assert_not_equal a.id, b.id
      assert_equal "legistar.sanjose", a.source_system
      assert_equal "legistar.santaclara", b.source_system
    end
  end
end
