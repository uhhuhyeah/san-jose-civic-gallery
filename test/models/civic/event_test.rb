require "test_helper"

module Civic
  class EventTest < ActiveSupport::TestCase
    test "requires legistar_event_id and event_date" do
      event = Event.new

      assert_not event.valid?
      assert_includes event.errors[:legistar_event_id], "can't be blank"
      assert_includes event.errors[:event_date], "can't be blank"
    end

    test "destroying an event destroys tombstone event items alongside source-present ones" do
      event = Event.create!(legistar_event_id: 99001, event_date: Date.new(2026, 5, 1))
      live_item = event.all_event_items.create!(legistar_event_item_id: 1001, title: "Live")
      tombstone = event.all_event_items.create!(
        legistar_event_item_id: 1002,
        title: "Removed upstream",
        source_present: false,
        source_missing_at: Time.current
      )

      assert_difference -> { EventItem.count }, -2 do
        event.destroy!
      end

      assert_not EventItem.exists?(live_item.id)
      assert_not EventItem.exists?(tombstone.id)
    end

    test "event_items association returns only source-present items" do
      event = Event.create!(legistar_event_id: 99002, event_date: Date.new(2026, 5, 1))
      live = event.all_event_items.create!(legistar_event_item_id: 2001, title: "Live")
      event.all_event_items.create!(
        legistar_event_item_id: 2002,
        title: "Tombstone",
        source_present: false,
        source_missing_at: Time.current
      )

      assert_equal [ live.id ], event.event_items.pluck(:id)
      assert_equal 2, event.all_event_items.count
    end
  end
end
