require "test_helper"

module Ingestion
  class PersistEventItemTest < ActiveSupport::TestCase
    setup do
      @event = Civic::Event.create!(
        legistar_event_id: 7622,
        body_name: "City Council",
        event_date: Date.new(2026, 5, 19)
      )
      @matter = Civic::Matter.create!(
        legistar_matter_id: 15915,
        matter_file: "26-602"
      )
    end

    test "persists an event item and raw snapshot" do
      event_item_payload = {
        "EventItemId" => 129630,
        "EventItemAgendaSequence" => 1,
        "EventItemMinutesSequence" => 1,
        "EventItemTitle" => "Public Comment",
        "EventItemMatterFile" => "CC 1.1",
        "EventItemMatterName" => "Agenda overview",
        "EventItemActionName" => "Approved",
        "EventItemPassedFlagName" => "Passed",
        "EventItemLastModifiedUtc" => "2026-05-11T22:27:16.64"
      }

      event_item, snapshot = PersistEventItem.call(
        event: @event,
        matter: @matter,
        event_item_payload:,
        source_system: "legistar.sanjose",
        request_url: "https://example.test/Events/7622/EventItems",
        fetched_at: Time.zone.parse("2026-05-15 08:00:00"),
        http_status: 200,
        response_sha256: "def456"
      )

      assert_equal 129630, event_item.legistar_event_item_id
      assert_equal @event.id, event_item.civic_event_id
      assert_equal @matter.id, event_item.civic_matter_id
      assert_equal "Public Comment", event_item.title
      assert_equal "CC 1.1", event_item.matter_file
      assert_equal "event_item", snapshot.resource_type
      assert_equal "129630", snapshot.source_id
      assert_equal "legistar.sanjose", event_item.source_system
      assert_equal snapshot.id, event_item.last_source_snapshot_id
    end
  end
end
