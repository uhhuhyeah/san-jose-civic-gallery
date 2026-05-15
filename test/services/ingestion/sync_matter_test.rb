require "test_helper"

module Ingestion
  class SyncMatterTest < ActiveSupport::TestCase
    setup do
      event = Civic::Event.create!(
        legistar_event_id: 7622,
        body_name: "City Council",
        event_date: Date.new(2026, 5, 19)
      )
      @event_item = event.all_event_items.create!(
        legistar_event_item_id: 129630,
        matter_id: 15886,
        title: "Agreement"
      )
      clear_enqueued_jobs
    end

    test "links previously persisted event items to the normalized matter" do
      client = Class.new do
        def source_system; "legistar.sanjose"; end

        def matter(matter_id:)
          raise "unexpected matter_id" unless matter_id == 15886

          {
            request_url: "https://example.test/Matters/15886",
            status: 200,
            fetched_at: Time.zone.parse("2026-05-15 10:00:00"),
            response_sha256: "matter-sha",
            payload: {
              "MatterId" => 15886,
              "MatterFile" => "26-575",
              "MatterTitle" => "Agreement approval",
              "MatterLastModifiedUtc" => "2026-05-15T09:00:00Z"
            }
          }
        end
      end.new

      result = SyncMatter.call(matter_id: 15886, client:, sync_attachments: false)

      @event_item.reload
      assert_equal result.matter.id, @event_item.civic_matter_id
      assert_enqueued_jobs 0
    end

    test "does not link event items from a different source_system" do
      other_source_event = Civic::Event.create!(
        source_system: "legistar.santaclara",
        legistar_event_id: 7622,
        body_name: "City Council",
        event_date: Date.new(2026, 5, 19)
      )
      other_item = other_source_event.all_event_items.create!(
        source_system: "legistar.santaclara",
        legistar_event_item_id: 555_555,
        matter_id: 15886,
        title: "Other-source item that happens to share matter id"
      )

      client = Class.new do
        def source_system; "legistar.sanjose"; end

        def matter(matter_id:)
          {
            request_url: "https://example.test/Matters/15886",
            status: 200,
            fetched_at: Time.current,
            response_sha256: "isolation-sha",
            payload: { "MatterId" => 15886, "MatterFile" => "26-575" }
          }
        end
      end.new

      result = SyncMatter.call(matter_id: 15886, client:, sync_attachments: false)

      @event_item.reload
      other_item.reload

      assert_equal result.matter.id, @event_item.civic_matter_id
      assert_nil other_item.civic_matter_id,
        "Item from a different source_system should NOT be linked to the sanjose matter"
    end
  end
end
