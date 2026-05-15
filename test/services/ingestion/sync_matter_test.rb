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
  end
end
